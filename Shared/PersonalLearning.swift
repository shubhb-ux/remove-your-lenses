import Foundation

struct DriftThresholds: Codable, Equatable {
    var heartRateDrop: Double = 0.08
    var quietSeconds: Double = 120
    static let standard = DriftThresholds()
    var isSupported: Bool {
        [0.06, 0.08, 0.10, 0.12].contains(heartRateDrop) && [90.0, 120, 150, 180].contains(quietSeconds)
    }
    var name: String { "hr\(Int((heartRateDrop * 100).rounded()))-quiet\(Int(quietSeconds))" }
}

/// Features observed live, not reconstructed using health samples delivered later.
struct TrialFeatureFrame: Codable {
    var time: Date
    var heartRateDrop: Double?
    var quietSeconds: Double
    var validSensors: Bool

    func triggers(_ thresholds: DriftThresholds) -> Bool {
        guard validSensors, let heartRateDrop, heartRateDrop.isFinite, quietSeconds.isFinite,
              thresholds.isSupported else { return false }
        return heartRateDrop >= thresholds.heartRateDrop && quietSeconds >= thresholds.quietSeconds
    }
}

struct LearningPolicy: Codable {
    var enabled = false
    var thresholds = DriftThresholds.standard
    var updatedAt = Date.distantPast
}

struct LearningScore: Codable, Equatable {
    var positives = 0
    var negatives = 0
    var missed = 0
    var falseAlarms = 0
    var evaluated: Int { positives + negatives }
    var loss: Int { missed * 2 + falseAlarms }
    mutating func add(_ evaluation: LearningEvaluation) {
        if evaluation.positive { positives += 1 } else { negatives += 1 }
        if evaluation.missed { missed += 1 }
        if evaluation.falseAlarm { falseAlarms += 1 }
    }
}

struct LearningEvaluation {
    var positive: Bool
    var missed: Bool
    var falseAlarm: Bool
}

struct LearningProposal: Codable {
    var thresholds: DriftThresholds
    var incumbent: DriftThresholds
    var createdAt: Date
    var trainingFingerprints: [String: String]
    var trainingScore: LearningScore
    var baselineScore: LearningScore
}

struct LearningState: Codable {
    var policy = LearningPolicy()
    var proposal: LearningProposal?
    var candidateValidation = LearningScore()
    var baselineValidation = LearningScore()
    var lastTrainingFingerprint: String?
    var status = "Learning is off. The standard experimental rule is used."
    var adoptedUpdates = 0
}

enum PersonalLearner {
    static let minimumTrainingTrials = 8
    static let minimumValidationPerClass = 3
    static var grid: [DriftThresholds] {
        [0.06, 0.08, 0.10, 0.12].flatMap { drop in
            [90.0, 120, 150, 180].map { DriftThresholds(heartRateDrop: drop, quietSeconds: $0) }
        }
    }

    private enum Label {
        case onset(Date, Date, Date) // onset and covered report bounds
        case awake(Date, Date)
    }

    private static func label(for trial: DriftTrial) -> Label? {
        guard let end = trial.endedAt, end > trial.startedAt else { return nil }
        if let eeg = trial.eegReference {
            // Never silently substitute a subjective label for an attached unaligned EEG report.
            guard eeg.alignmentConfirmed, eeg.validationError(for: trial) == nil else { return nil }
            if eeg.outcome == .awakeThroughout { return .awake(eeg.recordingStart, eeg.recordingEnd) }
            if let onset = eeg.sleepOnset, onset >= trial.startedAt, onset <= end {
                return .onset(onset, eeg.recordingStart, eeg.recordingEnd)
            }
            return nil
        }
        if trial.stayedAwakeThroughout == true,
           (trial.awakeUpdatedAt ?? .distantPast) >= (trial.sleepUpdatedAt ?? .distantPast) {
            return .awake(trial.startedAt, end)
        }
        if let onset = trial.estimatedSleepAt, onset >= trial.startedAt, onset <= end {
            return .onset(onset, trial.startedAt, end)
        }
        return nil // Drowsy or awake-at-one-alert feedback does not label an entire trial.
    }

    static func evaluate(_ trial: DriftTrial, thresholds: DriftThresholds) -> LearningEvaluation? {
        guard thresholds.isSupported, let label = label(for: trial), let end = trial.endedAt,
              let allFrames = trial.featureFrames else { return nil }
        let frames = allFrames.filter { $0.time >= trial.startedAt && $0.time <= end }
            .sorted { $0.time < $1.time }
        guard let firstUsable = frames.first(where: { $0.validSensors && $0.heartRateDrop?.isFinite == true }) else { return nil }
        // The rule needs baseline samples AND subsequent fresh samples: readiness can occur after minute five.
        // Compare only its observed usable interval, shared by every candidate threshold.
        let evaluationStart = max(trial.startedAt.addingTimeInterval(DriftCandidateRule.baselineSeconds), firstUsable.time)
        let prediction = frames.first { $0.time >= evaluationStart && $0.triggers(thresholds) }?.time
        switch label {
        case let .awake(coveredStart, coveredEnd):
            if let prediction {
                guard coveredStart <= prediction, coveredEnd >= prediction.addingTimeInterval(600) else { return nil }
                return LearningEvaluation(positive: false, missed: false, falseAlarm: true)
            }
            guard coveredStart <= evaluationStart, coveredEnd >= end,
                  end.timeIntervalSince(evaluationStart) >= 300,
                  hasCoverage(frames, from: evaluationStart, through: end) else { return nil }
            return LearningEvaluation(positive: false, missed: false, falseAlarm: false)
        case let .onset(onset, coveredStart, coveredEnd):
            if let prediction {
                let lead = onset.timeIntervalSince(prediction)
                if (0...600).contains(lead) {
                    return LearningEvaluation(positive: true, missed: false, falseAlarm: false)
                }
                if lead > 600 {
                    guard coveredStart <= prediction, coveredEnd >= prediction.addingTimeInterval(600) else { return nil }
                    return LearningEvaluation(positive: true, missed: true, falseAlarm: true)
                }
                // A prediction after sleep is a miss only if the preceding window was observed.
            }
            let begin = max(evaluationStart, onset.addingTimeInterval(-600))
            guard coveredStart <= begin, coveredEnd >= onset,
                  hasCoverage(frames, from: begin, through: onset) else { return nil }
            return LearningEvaluation(positive: true, missed: true, falseAlarm: false)
        }
    }

    private static func hasCoverage(_ frames: [TrialFeatureFrame], from start: Date, through end: Date) -> Bool {
        guard end.timeIntervalSince(start) >= 60 else { return false }
        let usable = frames.filter { $0.validSensors && $0.heartRateDrop?.isFinite == true && $0.time >= start && $0.time <= end }
        guard let first = usable.first, let last = usable.last,
              first.time.timeIntervalSince(start) <= 15, end.timeIntervalSince(last.time) <= 15 else { return false }
        return zip(usable, usable.dropFirst()).allSatisfy { $1.time.timeIntervalSince($0.time) <= 15 }
    }

    static func pairedScores(_ trials: [DriftTrial], candidate: DriftThresholds, baseline: DriftThresholds) -> (LearningScore, LearningScore) {
        var proposed = LearningScore(), current = LearningScore()
        for trial in trials {
            // Both versions must be evaluable on the exact same trials.
            guard let a = evaluate(trial, thresholds: candidate), let b = evaluate(trial, thresholds: baseline) else { continue }
            proposed.add(a); current.add(b)
        }
        return (proposed, current)
    }

    static func canAdopt(candidate: LearningScore, baseline: LearningScore) -> Bool {
        candidate.positives >= minimumValidationPerClass && candidate.negatives >= minimumValidationPerClass
            && candidate.positives == baseline.positives && candidate.negatives == baseline.negatives
            && candidate.missed <= baseline.missed && candidate.falseAlarms <= baseline.falseAlarms
            && candidate.loss < baseline.loss
    }

    static func fingerprint(_ trial: DriftTrial) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        // Stable across processes; not a security hash. Any training-record change invalidates its proposal.
        let bytes = (try? encoder.encode(trial)) ?? Data()
        var hash: UInt64 = 14695981039346656037
        for byte in bytes { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash, radix: 16)
    }

    static func refreshed(_ original: LearningState, trials: [DriftTrial], now: Date) -> LearningState {
        var state = original
        guard state.policy.enabled else { return state }
        let ended = trials.filter { $0.endedAt != nil }.sorted { $0.startedAt < $1.startedAt }
        if let proposal = state.proposal {
            let unchanged = proposal.trainingFingerprints.allSatisfy { id, fingerprint in
                ended.first(where: { $0.id.uuidString == id }).map { self.fingerprint($0) == fingerprint } ?? false
            }
            guard unchanged else {
                state.proposal = nil; state.lastTrainingFingerprint = nil
                state.candidateValidation = LearningScore(); state.baselineValidation = LearningScore()
                state.status = "Training data changed. The silent proposal was discarded; review will restart."
                return state
            }
            let future = ended.filter { $0.startedAt > proposal.createdAt && proposal.trainingFingerprints[$0.id.uuidString] == nil }
            let (candidate, baseline) = pairedScores(future, candidate: proposal.thresholds, baseline: proposal.incumbent)
            state.candidateValidation = candidate; state.baselineValidation = baseline
            if canAdopt(candidate: candidate, baseline: baseline) {
                state.policy.thresholds = proposal.thresholds
                state.policy.updatedAt = now
                state.adoptedUpdates += 1
                state.proposal = nil
                state.status = "Personalized settings adopted after separate later-trial checks. Improvement is not guaranteed on future nights."
            } else if candidate.positives >= minimumValidationPerClass && candidate.negatives >= minimumValidationPerClass {
                state.proposal = nil
                state.lastTrainingFingerprint = Array(ended.filter { trial in
                    grid.allSatisfy { evaluate(trial, thresholds: $0) != nil }
                }.suffix(20)).map(fingerprint).joined(separator: ":")
                state.status = "Candidate not adopted: later trials did not show fewer errors without increasing misses or false alarms. Keeping current alerts; waiting for new reviewed data."
            } else {
                state.status = "Testing silently: \(candidate.positives) sleep / \(candidate.negatives) awake trials evaluated. Need at least 3 of each and fewer errors without increasing either error type."
            }
            return state
        }

        // Training uses only records evaluable for every grid setting: no cherry-picked denominators.
        let training = Array(ended.filter { trial in grid.allSatisfy { evaluate(trial, thresholds: $0) != nil } }.suffix(20))
        let baseline = state.policy.thresholds
        let baselineScore = pairedScores(training, candidate: baseline, baseline: baseline).0
        guard training.count >= minimumTrainingTrials, baselineScore.positives >= 2, baselineScore.negatives >= 2 else {
            state.status = "Collecting examples: \(training.count)/8 usable trials (need at least 2 sleep and 2 awake). Older trials without live feature records cannot train."
            return state
        }
        let signature = training.map(fingerprint).joined(separator: ":")
        guard signature != state.lastTrainingFingerprint else { return state }
        state.lastTrainingFingerprint = signature
        let ranked = grid.map { thresholds -> (DriftThresholds, LearningScore) in
            (thresholds, pairedScores(training, candidate: thresholds, baseline: baseline).0)
        }.sorted {
            if $0.1.loss != $1.1.loss { return $0.1.loss < $1.1.loss }
            return $0.0.name < $1.0.name
        }
        guard let best = ranked.first, best.1.loss < baselineScore.loss,
              best.1.missed <= baselineScore.missed, best.1.falseAlarms <= baselineScore.falseAlarms else {
            state.status = "No better settings found on the reviewed examples. Keeping the current rule."
            return state
        }
        state.proposal = LearningProposal(thresholds: best.0, incumbent: baseline, createdAt: now,
            trainingFingerprints: Dictionary(uniqueKeysWithValues: training.map { ($0.id.uuidString, fingerprint($0)) }),
            trainingScore: best.1, baselineScore: baselineScore)
        state.candidateValidation = LearningScore(); state.baselineValidation = LearningScore()
        state.status = "A candidate was fitted. It will be tested on new trials started after today; current alerts are unchanged."
        return state
    }
}
