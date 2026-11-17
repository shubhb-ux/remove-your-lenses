import Foundation

struct TrialHeartSample: Codable, Identifiable {
    var id: UUID
    var time: Date
    var bpm: Double
    var receivedAt: Date?
}

struct TrialMotionSample: Codable {
    var time: Date
    var quietSeconds: Double
    var coverageSeconds: Double
}

enum TrialAlertFeedback: String, Codable, CaseIterable {
    case unreviewed, awake, drowsy
    var title: String {
        switch self {
        case .unreviewed: return "Not reviewed"
        case .awake: return "I was awake"
        case .drowsy: return "I felt drowsy"
        }
    }
}

struct DriftTrial: Identifiable, Codable {
    static let modelVersion = "experimental-hr-motion-v2"
    var id = UUID()
    var startedAt = Date()
    var endedAt: Date?
    var modelVersion = Self.modelVersion
    var heart: [TrialHeartSample] = []
    var motion: [TrialMotionSample] = []
    var candidateAt: Date?
    var backupAt: Date?
    var feedback: TrialAlertFeedback = .unreviewed
    var estimatedSleepAt: Date?
    var endReason = "Running"
    var notes: [String] = []
    // Separate clocks prevent an older sensor snapshot overwriting a newer review.
    var dataUpdatedAt: Date?
    var feedbackUpdatedAt: Date?
    var sleepUpdatedAt: Date?
    var eegReference: EEGSleepReference?
    var eegUpdatedAt: Date?
    var stayedAwakeThroughout: Bool?
    var awakeUpdatedAt: Date?
    var featureFrames: [TrialFeatureFrame]?
    var usedThresholds: DriftThresholds?

    var warningSeconds: TimeInterval? {
        guard let sleep = estimatedSleepAt, let alert = candidateAt else { return nil }
        return sleep.timeIntervalSince(alert)
    }
    /// Only self-reported sleep with a completed observation window is evaluated.
    var selfReportedMiss: Bool? {
        guard let sleep = estimatedSleepAt, let end = endedAt,
              sleep >= startedAt, sleep <= end else { return nil }
        guard let candidateAt else { return true }
        let lead = sleep.timeIntervalSince(candidateAt)
        return !(0...600).contains(lead)
    }
}

/// Deliberately unvalidated candidate rule. It does not output a sleep diagnosis or probability.
struct DriftCandidateRule {
    static let baselineSeconds: TimeInterval = 300
    private(set) var quietSeconds: TimeInterval = 0
    private var quietSince: TimeInterval?
    private var lastMotionTime: TimeInterval?
    private var previousAcceleration: (Double, Double, Double)?
    private(set) var baselineBPM: Double?
    private(set) var latestFeatures: TrialFeatureFrame?
    let thresholds: DriftThresholds

    init(thresholds: DriftThresholds = .standard) {
        self.thresholds = thresholds.isSupported ? thresholds : .standard
    }

    mutating func addMotion(x: Double, y: Double, z: Double, time: TimeInterval) {
        guard [x, y, z, time].allSatisfy(\.isFinite) else { resetMotion(); return }
        defer { lastMotionTime = time; previousAcceleration = (x, y, z) }
        guard let last = lastMotionTime, let previous = previousAcceleration,
              time > last, time - last <= 3 else { quietSince = nil; quietSeconds = 0; return }
        let delta = sqrt(pow(x - previous.0, 2) + pow(y - previous.1, 2) + pow(z - previous.2, 2))
        let magnitude = sqrt(x*x + y*y + z*z)
        guard delta < 0.025, abs(magnitude - 1) < 0.06 else {
            quietSince = nil; quietSeconds = 0; return
        }
        if quietSince == nil { quietSince = time }
        quietSeconds = time - (quietSince ?? time)
    }

    mutating func resetMotion() {
        quietSeconds = 0; quietSince = nil; lastMotionTime = nil; previousAcceleration = nil
    }

    mutating func evaluate(trial: DriftTrial, now: Date) -> String {
        latestFeatures = TrialFeatureFrame(time: now, heartRateDrop: nil,
            quietSeconds: quietSeconds, validSensors: false)
        guard now.timeIntervalSince(trial.startedAt) >= Self.baselineSeconds else {
            return "Learning your awake baseline (first 5 minutes)"
        }
        let baselineEnd = trial.startedAt.addingTimeInterval(Self.baselineSeconds)
        let baseline = trial.heart.filter { $0.time >= trial.startedAt && $0.time < baselineEnd }
            .sorted { $0.time < $1.time }
        guard baseline.count >= 3,
              baseline.last!.time.timeIntervalSince(baseline.first!.time) >= 120 else {
            return "Not enough baseline heart-rate data; no estimate"
        }
        let sorted = baseline.map(\.bpm).sorted()
        baselineBPM = median(sorted)
        let recent = trial.heart.filter { $0.time >= baselineEnd && $0.time <= now && now.timeIntervalSince($0.time) <= 180 }
            .sorted { $0.time < $1.time }
        guard recent.count >= 3,
              recent.last!.time.timeIntervalSince(recent.first!.time) >= 60,
              now.timeIntervalSince(recent.last!.time) <= 60 else {
            return "Waiting for fresh heart-rate samples; no estimate"
        }
        guard let lastMotionTime, now.timeIntervalSince1970 - lastMotionTime <= 3,
              now.timeIntervalSince1970 >= lastMotionTime else {
            return "Monitoring heart rate and movement"
        }
        let values = recent.map(\.bpm).sorted()
        let recentMedian = median(values)
        guard let baselineBPM, baselineBPM > 0 else { return "No baseline" }
        let features = TrialFeatureFrame(time: now, heartRateDrop: (baselineBPM - recentMedian) / baselineBPM,
            quietSeconds: quietSeconds, validSensors: true)
        latestFeatures = features
        return features.triggers(thresholds) ? "candidate" : "No combined signal yet"
    }
    private func median(_ sorted: [Double]) -> Double {
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

/// Acquisition and review edits travel independently between paired devices.
enum TrialMerge {
    static func merge(local: DriftTrial, incoming: DriftTrial) -> DriftTrial {
        guard local.id == incoming.id else { return local }
        let localData = local.dataUpdatedAt ?? local.endedAt ?? local.motion.last?.time ?? local.startedAt
        let incomingData = incoming.dataUpdatedAt ?? incoming.endedAt ?? incoming.motion.last?.time ?? incoming.startedAt
        var result = incomingData > localData ? incoming : local
        let useIncomingFeedback = (incoming.feedbackUpdatedAt ?? .distantPast) > (local.feedbackUpdatedAt ?? .distantPast)
            || (local.feedbackUpdatedAt == nil && incoming.feedbackUpdatedAt == nil && local.feedback == .unreviewed && incoming.feedback != .unreviewed)
        let feedback = useIncomingFeedback ? incoming : local
        result.feedback = feedback.feedback
        result.feedbackUpdatedAt = feedback.feedbackUpdatedAt
        let useIncomingSleep = (incoming.sleepUpdatedAt ?? .distantPast) > (local.sleepUpdatedAt ?? .distantPast)
            || (local.sleepUpdatedAt == nil && incoming.sleepUpdatedAt == nil && local.estimatedSleepAt == nil && incoming.estimatedSleepAt != nil)
        let sleep = useIncomingSleep ? incoming : local
        result.estimatedSleepAt = sleep.estimatedSleepAt
        result.sleepUpdatedAt = sleep.sleepUpdatedAt
        let useIncomingEEG = (incoming.eegUpdatedAt ?? .distantPast) > (local.eegUpdatedAt ?? .distantPast)
            || (local.eegUpdatedAt == nil && incoming.eegUpdatedAt == nil && local.eegReference == nil && incoming.eegReference != nil)
        let eeg = useIncomingEEG ? incoming : local
        result.eegReference = eeg.eegReference
        result.eegUpdatedAt = eeg.eegUpdatedAt
        let useIncomingAwake = (incoming.awakeUpdatedAt ?? .distantPast) > (local.awakeUpdatedAt ?? .distantPast)
        let awake = useIncomingAwake ? incoming : local
        result.stayedAwakeThroughout = awake.stayedAwakeThroughout
        result.awakeUpdatedAt = awake.awakeUpdatedAt
        return result
    }
}
