import Foundation
import Observation

@MainActor @Observable
final class LearningCoordinator {
    static let shared = LearningCoordinator()
    private(set) var state = LearningState()
    private(set) var storageError: String?
    private var folder: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] }
    private var stateURL: URL { folder.appendingPathComponent("personal-learning-state.json") }
    var effectiveThresholds: DriftThresholds {
        state.policy.enabled && state.policy.thresholds.isSupported ? state.policy.thresholds : .standard
    }

    private init() {
        if FileManager.default.fileExists(atPath: stateURL.path) {
            do { state = try JSONDecoder().decode(LearningState.self, from: Data(contentsOf: stateURL)) }
            catch { storageError = "Could not load learning settings. The standard rule is used."; state = LearningState() }
        }
    }

    func refresh(using trials: [DriftTrial]) {
        #if os(iOS)
        let next = PersonalLearner.refreshed(state, trials: trials, now: Date())
        let policyChanged = next.policy.updatedAt != state.policy.updatedAt
        if persist(next), policyChanged { publishPolicy() }
        #endif
    }

    func setEnabled(_ enabled: Bool) {
        #if os(iOS)
        var next = state
        next.policy.enabled = enabled
        next.policy.updatedAt = Date()
        if !enabled {
            next.proposal = nil
            next.lastTrainingFingerprint = nil
            next.status = "Learning is off. The standard experimental rule is used."
        }
        if persist(next) {
            publishPolicy()
            refresh(using: TrialArchive.shared.trials)
        }
        #endif
    }

    func reset() {
        #if os(iOS)
        var next = LearningState()
        next.policy.updatedAt = Date()
        if persist(next) { publishPolicy() }
        #endif
    }

    func sendPolicyAgain() {
        #if os(iOS)
        publishPolicy()
        #endif
    }

    func receivePolicy(_ data: Data) {
        #if os(watchOS)
        guard data.count < 10_000, let policy = try? JSONDecoder().decode(LearningPolicy.self, from: data),
              policy.thresholds.isSupported, policy.updatedAt > state.policy.updatedAt else { return }
        var next = state
        next.policy = policy
        next.status = policy.enabled ? "Learning settings received from iPhone; applied at the next trial start."
            : "Learning is off. The standard experimental rule is used."
        _ = persist(next)
        #endif
    }

    @discardableResult
    private func persist(_ next: LearningState) -> Bool {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: stateURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            state = next
            storageError = nil
            return true
        } catch { storageError = error.localizedDescription; return false }
    }

    private func publishPolicy() {
        do {
            let url = folder.appendingPathComponent("learning-config.json")
            try JSONEncoder().encode(state.policy).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            TrialTransfer.shared.send(url)
        } catch { storageError = error.localizedDescription }
    }
}
