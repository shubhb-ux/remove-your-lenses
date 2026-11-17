import Foundation
import Observation
import WatchConnectivity

@MainActor @Observable
final class TrialArchive {
    static let shared = TrialArchive()
    private(set) var trials: [DriftTrial] = []
    private(set) var storageError: String?
    @ObservationIgnored private var deletedIDs = Set(UserDefaults.standard.stringArray(forKey: "deletedDriftTrialIDs") ?? [])
    private var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DriftTrials", isDirectory: true)
    }
    init() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            trials = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .compactMap { try? JSONDecoder().decode(DriftTrial.self, from: Data(contentsOf: $0)) }
                .filter { !deletedIDs.contains($0.id.uuidString) }
                .sorted { $0.startedAt > $1.startedAt }
            #if os(watchOS)
            for index in trials.indices where trials[index].endedAt == nil {
                var interrupted = trials[index]
                interrupted.endedAt = interrupted.motion.last?.time ?? interrupted.startedAt
                interrupted.endReason = "Interrupted; sensor coverage incomplete"
                if persist(interrupted) { trials[index] = interrupted }
            }
            #endif
        } catch { storageError = error.localizedDescription }
    }

    @discardableResult
    func save(_ trial: DriftTrial, transfer: Bool = false, updateSensorRecord: Bool = true) -> Bool {
        guard !deletedIDs.contains(trial.id.uuidString) else { return false }
        var candidate = trial
        if updateSensorRecord { candidate.dataUpdatedAt = Date() }
        if let existing = trials.first(where: { $0.id == trial.id }) {
            candidate = TrialMerge.merge(local: existing, incoming: candidate)
        }
        guard persist(candidate) else { return false }
        if let index = trials.firstIndex(where: { $0.id == candidate.id }) { trials[index] = candidate }
        else { trials.append(candidate); trials.sort { $0.startedAt > $1.startedAt } }
        if transfer { TrialTransfer.shared.send(url(for: candidate)) }
        #if os(iOS)
        LearningCoordinator.shared.refresh(using: trials)
        #endif
        return true
    }
    @discardableResult
    private func persist(_ trial: DriftTrial) -> Bool {
        do {
            try JSONEncoder().encode(trial).write(to: url(for: trial), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            storageError = nil
            return true
        } catch { storageError = error.localizedDescription; return false }
    }
    func url(for trial: DriftTrial) -> URL { folder.appendingPathComponent("\(trial.id.uuidString).json") }
    func importData(_ data: Data) {
        guard data.count <= 5_000_000,
              let trial = try? JSONDecoder().decode(DriftTrial.self, from: data),
              !deletedIDs.contains(trial.id.uuidString) else { return }
        save(trial, updateSensorRecord: false)
    }
    func label(_ id: UUID, feedback: TrialAlertFeedback) {
        guard var trial = trials.first(where: { $0.id == id }) else { return }
        trial.feedback = feedback; trial.feedbackUpdatedAt = Date()
        save(trial, transfer: true, updateSensorRecord: false)
    }
    func recordSleep(_ id: UUID, at date: Date?) {
        guard var trial = trials.first(where: { $0.id == id }) else { return }
        if let date {
            guard let end = trial.endedAt, date >= trial.startedAt, date <= end else { return }
        }
        trial.estimatedSleepAt = date; trial.sleepUpdatedAt = Date()
        if date != nil { trial.stayedAwakeThroughout = nil; trial.awakeUpdatedAt = Date() }
        save(trial, transfer: true, updateSensorRecord: false)
    }
    func recordStayedAwake(_ id: UUID, awake: Bool) {
        guard var trial = trials.first(where: { $0.id == id }), trial.endedAt != nil else { return }
        trial.stayedAwakeThroughout = awake ? true : nil
        trial.awakeUpdatedAt = Date()
        if awake { trial.estimatedSleepAt = nil; trial.sleepUpdatedAt = Date() }
        save(trial, transfer: true, updateSensorRecord: false)
    }

    func recordEEG(_ id: UUID, reference: EEGSleepReference?) throws {
        guard var trial = trials.first(where: { $0.id == id }) else {
            throw EEGReferenceError(message: "This trial is no longer available.")
        }
        guard trial.endedAt != nil else { throw EEGReferenceError(message: "Finish the trial first.") }
        if let reference, let error = reference.validationError(for: trial) {
            throw EEGReferenceError(message: error)
        }
        trial.eegReference = reference
        trial.eegUpdatedAt = Date()
        guard save(trial, transfer: true, updateSensorRecord: false) else {
            throw EEGReferenceError(message: storageError ?? "Could not save the EEG reference.")
        }
    }

    func delete(_ trial: DriftTrial) {
        guard trial.endedAt != nil else { return }
        do {
            if FileManager.default.fileExists(atPath: url(for: trial).path) {
                try FileManager.default.removeItem(at: url(for: trial))
            }
            deletedIDs.insert(trial.id.uuidString)
            UserDefaults.standard.set(Array(deletedIDs), forKey: "deletedDriftTrialIDs")
            trials.removeAll { $0.id == trial.id }
            TrialTransfer.shared.cancelQueued(trialID: trial.id.uuidString)
            storageError = nil
            #if os(iOS)
            LearningCoordinator.shared.refresh(using: trials)
            #endif
        } catch { storageError = error.localizedDescription }
    }
}

@MainActor @Observable
final class TrialTransfer: NSObject, WCSessionDelegate {
    static let shared = TrialTransfer()
    private(set) var lastError: String?
    private var outbox: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrialOutbox", isDirectory: true)
    }
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        if WCSession.default.activationState == .activated { flush() }
        else { WCSession.default.activate() }
    }
    func send(_ url: URL) {
        guard WCSession.isSupported() else { lastError = "Trial transfer is not available on this device."; return }
        do {
            try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
            let name = "\(url.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).json"
            // Immutable snapshots remain valid even when a live trial is edited or deleted.
            let data = try Data(contentsOf: url)
            try data.write(to: outbox.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            lastError = nil
            activate()
        } catch { lastError = error.localizedDescription }
    }
    private func flush() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        do {
            guard FileManager.default.fileExists(atPath: outbox.path) else { return }
            let inFlight = Set(session.outstandingFileTransfers.compactMap { $0.file.metadata?["queueID"] as? String })
            for file in try FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil)
                where file.pathExtension == "json" && !inFlight.contains(file.lastPathComponent) {
                let kind = file.lastPathComponent.hasPrefix("learning-config-") ? "learning-config" : "drift-trial"
                session.transferFile(file, metadata: ["kind": kind, "queueID": file.lastPathComponent])
            }
        } catch { lastError = error.localizedDescription }
    }
    func cancelQueued(trialID: String) {
        guard WCSession.isSupported() else { return }
        for transfer in WCSession.default.outstandingFileTransfers {
            if (transfer.file.metadata?["queueID"] as? String)?.hasPrefix(trialID + "-") == true { transfer.cancel() }
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(trialID + "-") { try? FileManager.default.removeItem(at: file) }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error { self.lastError = error.localizedDescription }
            if activationState == .activated { self.flush() }
        }
    }
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let name = fileTransfer.file.metadata?["queueID"] as? String
        Task { @MainActor in
            if let error { self.lastError = "Transfer queued for retry: \(error.localizedDescription)"; return }
            if let name, name == URL(fileURLWithPath: name).lastPathComponent {
                try? FileManager.default.removeItem(at: self.outbox.appendingPathComponent(name))
            }
        }
    }
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let kind = file.metadata?["kind"] as? String,
              let data = try? Data(contentsOf: file.fileURL) else { return }
        Task { @MainActor in
            if kind == "drift-trial" { TrialArchive.shared.importData(data) }
            else if kind == "learning-config" { LearningCoordinator.shared.receivePolicy(data) }
        }
    }
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
