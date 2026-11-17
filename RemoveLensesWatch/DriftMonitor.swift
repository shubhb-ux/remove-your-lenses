import CoreMotion
import HealthKit
import Observation
import WatchKit

@MainActor @Observable
final class DriftMonitor: NSObject, WKExtendedRuntimeSessionDelegate {
    static let shared = DriftMonitor()
    private(set) var isActive = false
    private(set) var starting = false
    private(set) var status = "Not running"
    private(set) var current: DriftTrial?
    private(set) var heartCount = 0
    private(set) var quietSeconds = 0
    @ObservationIgnored private var rule = DriftCandidateRule()
    @ObservationIgnored private let health = HKHealthStore()
    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var query: HKAnchoredObjectQuery?
    @ObservationIgnored private var session: WKExtendedRuntimeSession?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var lastMotion: Date?
    @ObservationIgnored private var lastCheckpoint = Date.distantPast
    @ObservationIgnored private var coverage: TimeInterval = 0
    private let activeKey = "activeDriftTrialID"

    func start() async {
        guard !isActive, !starting else { return }
        guard LensStore.shared.lensesAreIn else { status = "Mark lenses in before starting a check."; return }
        guard motion.isAccelerometerAvailable, HKHealthStore.isHealthDataAvailable() else {
            status = "Needs a real Apple Watch with motion and Health data. No sensor results are simulated."
            return
        }
        guard TrialArchive.shared.storageError == nil else { status = "Trial storage unavailable."; return }
        guard TrialArchive.shared.trials.count < 30 else { status = "Export or delete an old trial first (30-trial limit)."; return }
        let authorization = CMMotionActivityManager.authorizationStatus()
        guard authorization != .denied, authorization != .restricted else { status = "Enable Motion & Fitness access in Settings."; return }
        starting = true
        let token = UUID(); generation = token
        defer { starting = false }
        do {
            guard await ReminderScheduler.shared.requestPermission() else {
                status = "Enable notifications to start a check."; return
            }
            guard generation == token else { return }
            let type = HKQuantityType.quantityType(forIdentifier: .heartRate)!
            try await health.requestAuthorization(toShare: [], read: [type])
            guard generation == token else { return }
            try await ReminderScheduler.shared.scheduleTrialBackup()
            guard generation == token, LensStore.shared.lensesAreIn else {
                ReminderScheduler.shared.cancelTrialAlerts(); return
            }
            let settings = LearningCoordinator.shared.effectiveThresholds
            current = DriftTrial()
            current?.featureFrames = []
            current?.usedThresholds = settings
            current?.modelVersion = "\(DriftTrial.modelVersion)-\(settings.name)"
            current?.notes.append("Unvalidated heart-rate + movement rule. Health permission completion does not guarantee read access or fresh samples.")
            rule = DriftCandidateRule(thresholds: settings); heartCount = 0; quietSeconds = 0; coverage = 0
            isActive = true; status = "Starting 30-minute trial"
            if let current {
                guard TrialArchive.shared.save(current) else {
                    isActive = false
                    self.current = nil
                    ReminderScheduler.shared.cancelTrialAlerts()
                    status = "Could not save trial. Check storage and try again."
                    return
                }
                UserDefaults.standard.set(current.id.uuidString, forKey: activeKey)
            }
            let created = WKExtendedRuntimeSession(); session = created; created.delegate = self
            created.start(at: Date().addingTimeInterval(1))
        } catch { status = "Could not start: \(error.localizedDescription)" }
    }

    func resume(_ resumed: WKExtendedRuntimeSession) {
        session = resumed; resumed.delegate = self
        let id = UserDefaults.standard.string(forKey: activeKey)
        current = TrialArchive.shared.trials.first { $0.id.uuidString == id }
        guard current != nil else { resumed.invalidate(); status = "Trial record missing. Timed backup remains scheduled."; return }
        current?.endedAt = nil
        current?.notes.append("Session resumed; any gap is not treated as continuous motion coverage.")
        isActive = true; rule = DriftCandidateRule(thresholds: current?.usedThresholds ?? .standard); coverage = current?.motion.last?.coverageSeconds ?? 0
        if resumed.state == .running { beginSampling() }
    }

    func stop() {
        if starting && !isActive {
            generation = UUID()
            ReminderScheduler.shared.cancelTrialAlerts()
            status = "Start cancelled"
            return
        }
        guard isActive else { return }
        finish(reason: "Stopped by user", cancelBackup: true)
    }
    func lensesRemoved() { if isActive { finish(reason: "Lenses removed", cancelBackup: true) } }

    private func beginSampling() {
        guard query == nil, timer == nil else { return }
        guard LensStore.shared.lensesAreIn else { lensesRemoved(); return }
        if current?.candidateAt != nil || current?.backupAt != nil {
            status = "Reminder already issued. Stop the check or confirm removal."
            return
        }
        let token = generation
        lastMotion = nil; lastCheckpoint = .distantPast
        motion.accelerometerUpdateInterval = 0.5
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            Task { @MainActor in
                guard let self, self.generation == token, self.isActive else { return }
                guard error == nil, let data else {
                    self.status = "Motion unavailable; no drowsiness estimate. Timed backup is set."
                    self.rule.resetMotion(); self.motion.stopAccelerometerUpdates(); return
                }
                let now = Date()
                let sampleTime = now.timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime + data.timestamp
                if let last = self.lastMotion {
                    let interval = sampleTime - last.timeIntervalSince1970
                    if interval > 0, interval <= 3 { self.coverage += interval }
                }
                self.lastMotion = Date(timeIntervalSince1970: sampleTime)
                let a = data.acceleration
                self.rule.addMotion(x: a.x, y: a.y, z: a.z, time: sampleTime)
                self.quietSeconds = Int(self.rule.quietSeconds)
            }
        }
        let type = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: current?.startedAt, end: nil, options: .strictStartDate)
        let receive: @Sendable (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { [weak self] _, samples, deleted, _, error in
            Task { @MainActor in
                guard let self, self.generation == token, self.isActive else { return }
                if let error { self.current?.notes.append("Health query: \(error.localizedDescription)") }
                let deletedIDs = Set((deleted ?? []).map(\.uuid))
                self.current?.heart.removeAll { deletedIDs.contains($0.id) }
                for sample in (samples as? [HKQuantitySample] ?? []) {
                    guard sample.sourceRevision.productType?.hasPrefix("Watch") == true,
                          sample.endDate <= Date(), sample.startDate >= (self.current?.startedAt ?? .distantFuture),
                          self.current?.heart.contains(where: { $0.id == sample.uuid }) == false else { continue }
                    let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    guard bpm.isFinite, bpm > 0, bpm < 300 else { continue }
                    self.current?.heart.append(TrialHeartSample(id: sample.uuid, time: sample.endDate, bpm: bpm, receivedAt: Date()))
                }
                self.heartCount = self.current?.heart.count ?? 0
            }
        }
        let heartQuery = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: receive)
        heartQuery.updateHandler = receive; query = heartQuery; health.execute(heartQuery)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
    }

    private func evaluate() {
        guard isActive, var trial = current else { return }
        guard LensStore.shared.lensesAreIn else { lensesRemoved(); return }
        let now = Date()
        if let expiration = session?.expirationDate, expiration.timeIntervalSince(now) <= 60,
           trial.candidateAt == nil, trial.backupAt == nil {
            alert(candidate: false); return
        }
        let freshMotion = lastMotion.map { now.timeIntervalSince($0) <= 3 } ?? false
        if !freshMotion { rule.resetMotion(); quietSeconds = 0 }
        let evaluation = rule.evaluate(trial: trial, now: now)
        if let frame = rule.latestFeatures { trial.featureFrames = (trial.featureFrames ?? []) + [frame] }
        if trial.candidateAt == nil && trial.backupAt == nil {
            status = freshMotion ? evaluation : "Motion missing; no estimate. Timed backup is set."
        }
        current = trial
        if now.timeIntervalSince(lastCheckpoint) >= 30 {
            trial.motion.append(TrialMotionSample(time: now, quietSeconds: rule.quietSeconds, coverageSeconds: coverage))
            current = trial; TrialArchive.shared.save(trial); lastCheckpoint = now
        }
        if TrialArchive.shared.storageError != nil { finish(reason: "Storage failed; data incomplete", cancelBackup: false); return }
        if freshMotion && evaluation == "candidate" { alert(candidate: true) }
    }

    private func alert(candidate: Bool) {
        guard let session, session.state == .running, current?.candidateAt == nil, current?.backupAt == nil else { return }
        let now = Date()
        checkpointLastMotion()
        if candidate { current?.candidateAt = now }
        else { current?.backupAt = now }
        status = candidate ? "Possible drowsiness — remove your lenses" : "Timed backup — remove your lenses"
        // Keep collecting until Stop/removal/expiry so silent candidate settings can be evaluated.
        if let current { TrialArchive.shared.save(current) }
        session.notifyUser(hapticType: .notification, repeatHandler: { _ in 10 })
        ReminderScheduler.shared.cancelTrialAlerts()
        let token = generation
        Task {
            guard self.generation == token, self.isActive, LensStore.shared.lensesAreIn else { return }
            await ReminderScheduler.shared.sendTrialAlert(candidate: candidate)
        }
    }

    private func finish(reason: String, cancelBackup: Bool) {
        generation = UUID(); isActive = false
        checkpointLastMotion()
        cleanup()
        if var trial = current {
            trial.endedAt = Date(); trial.endReason = reason
            if let reviewed = TrialArchive.shared.trials.first(where: { $0.id == trial.id }) {
                trial.feedback = reviewed.feedback
                trial.estimatedSleepAt = reviewed.estimatedSleepAt
            }
            TrialArchive.shared.save(trial, transfer: true); current = trial
        }
        UserDefaults.standard.removeObject(forKey: activeKey)
        let old = session; session = nil
        if old?.state == .running || old?.state == .scheduled { old?.invalidate() }
        if cancelBackup { ReminderScheduler.shared.cancelTrialAlerts() }
        status = reason
    }
    private func checkpointLastMotion() {
        guard let lastMotion,
              lastMotion > (current?.motion.last?.time ?? .distantPast) else { return }
        current?.motion.append(TrialMotionSample(time: lastMotion,
            quietSeconds: rule.quietSeconds, coverageSeconds: coverage))
    }

    private func cleanup() {
        motion.stopAccelerometerUpdates()
        if let query { health.stop(query) }; query = nil
        timer?.invalidate(); timer = nil
    }
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            guard self.session === extendedRuntimeSession else { return }; self.beginSampling()
        }
    }
    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            guard self.session === extendedRuntimeSession else { return }; self.alert(candidate: false)
        }
    }
    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        Task { @MainActor in
            guard self.session === extendedRuntimeSession else { return }
            self.finish(reason: error.map { "System ended check: \($0.localizedDescription)" } ?? "Session ended", cancelBackup: false)
        }
    }
}

@MainActor
final class DriftWatchDelegate: NSObject, WKApplicationDelegate {
    func handle(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        extendedRuntimeSession.delegate = DriftMonitor.shared
        DriftMonitor.shared.resume(extendedRuntimeSession)
    }
}
