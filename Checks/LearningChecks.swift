
func learningTrial(_ offset: TimeInterval, sleep: Bool) -> DriftTrial {
    let begin = start.addingTimeInterval(offset)
    var t = DriftTrial(startedAt: begin)
    t.endedAt = begin.addingTimeInterval(1800)
    if sleep { t.estimatedSleepAt = begin.addingTimeInterval(1200); t.sleepUpdatedAt = t.endedAt }
    else { t.stayedAwakeThroughout = true; t.awakeUpdatedAt = t.endedAt }
    t.featureFrames = stride(from: 300, through: 1800, by: 5).map { second in
        TrialFeatureFrame(time: begin.addingTimeInterval(Double(second)),
            heartRateDrop: sleep && second >= 900 ? 0.07 : 0.02,
            quietSeconds: second >= 900 ? 150 : 0, validSensors: second >= 365)
    }
    return t
}
var trainingTrials = (0..<8).map { learningTrial(Double($0) * 86400, sleep: $0 < 4) }
let trainedAt = start.addingTimeInterval(9 * 86400)
var enabledState = LearningState(); enabledState.policy.enabled = true
let proposedState = PersonalLearner.refreshed(enabledState, trials: trainingTrials, now: trainedAt)
check(proposedState.proposal != nil, "sufficient labeled examples fit a silent candidate")
check(proposedState.policy.thresholds == .standard, "fitting never changes active alerts immediately")
check(proposedState.proposal!.trainingFingerprints.count == 8, "proposal records its training trial identities")
let insufficient = PersonalLearner.refreshed(enabledState, trials: Array(trainingTrials.prefix(7)), now: trainedAt)
check(insufficient.proposal == nil, "fewer than eight usable trials cannot fit")
let onlySleep = (0..<8).map { learningTrial(Double($0) * 86400, sleep: true) }
check(PersonalLearner.refreshed(enabledState, trials: onlySleep, now: trainedAt).proposal == nil, "training requires awake and sleep examples")
var disabledState = LearningState()
check(PersonalLearner.refreshed(disabledState, trials: trainingTrials, now: trainedAt).proposal == nil, "learning is opt-in")
let reused = PersonalLearner.refreshed(proposedState, trials: trainingTrials, now: trainedAt.addingTimeInterval(100))
check(reused.candidateValidation.evaluated == 0 && reused.policy.thresholds == .standard, "training trials cannot validate their own proposal")
let futureTrials = (0..<6).map { learningTrial(10 * 86400 + Double($0) * 86400, sleep: $0 < 3) }
let limited = PersonalLearner.refreshed(proposedState, trials: trainingTrials + Array(futureTrials.prefix(5)), now: trainedAt.addingTimeInterval(10 * 86400))
check(limited.policy.thresholds == .standard, "insufficient future awake coverage cannot promote")
let adopted = PersonalLearner.refreshed(proposedState, trials: trainingTrials + futureTrials, now: trainedAt.addingTimeInterval(10 * 86400))
check(adopted.policy.thresholds != .standard && adopted.adoptedUpdates == 1, "separate future evidence can adopt lower-error thresholds")
check(adopted.candidateValidation.missed == 0 && adopted.baselineValidation.missed == 3, "future scores compare the same labeled trials")
var editedTraining = trainingTrials
editedTraining[0].estimatedSleepAt = editedTraining[0].startedAt.addingTimeInterval(1500)
let invalidated = PersonalLearner.refreshed(proposedState, trials: editedTraining + futureTrials, now: trainedAt.addingTimeInterval(20 * 86400))
check(invalidated.proposal == nil && invalidated.adoptedUpdates == 0, "editing a training label invalidates the frozen candidate")
check(PersonalLearner.refreshed(proposedState, trials: Array(trainingTrials.dropFirst()) + futureTrials, now: trainedAt).proposal == nil, "deleting training data invalidates the candidate")
var unreviewedTrial = learningTrial(0, sleep: false)
unreviewedTrial.stayedAwakeThroughout = nil
unreviewedTrial.feedback = .awake
unreviewedTrial.candidateAt = unreviewedTrial.startedAt.addingTimeInterval(900)
check(PersonalLearner.evaluate(unreviewedTrial, thresholds: .standard) == nil, "awake at one alert is not assumed awake throughout")
var truncated = learningTrial(0, sleep: true)
let truncationTime = truncated.startedAt.addingTimeInterval(950)
truncated.featureFrames?.removeAll { $0.time > truncationTime }
let paired = PersonalLearner.pairedScores([truncated], candidate: proposedState.proposal!.thresholds, baseline: .standard)
check(paired.0.evaluated == 0 && paired.1.evaluated == 0, "censored recordings do not give versions different denominators")
var missing = learningTrial(0, sleep: true)
missing.featureFrames = nil
check(PersonalLearner.evaluate(missing, thresholds: .standard) == nil, "legacy trials without observed features cannot train")
var noHeartFrames = learningTrial(0, sleep: true)
noHeartFrames.featureFrames = noHeartFrames.featureFrames?.map { frame in
    var f = frame; f.validSensors = false; f.heartRateDrop = nil; return f
}
check(PersonalLearner.evaluate(noHeartFrames, thresholds: .standard) == nil, "missing sensor data is never a successful no-alert result")
var unaligned = learningTrial(0, sleep: true)
unaligned.eegReference = EEGSleepReference(source: "EEG report", recordingStart: unaligned.startedAt,
    recordingEnd: unaligned.endedAt!, outcome: .sleepOnset, sleepOnset: unaligned.estimatedSleepAt,
    timeZoneIdentifier: "UTC", alignmentConfirmed: false)
check(PersonalLearner.evaluate(unaligned, thresholds: .standard) == nil, "unaligned attached EEG is not silently replaced with subjective labels")
let worseMisses = LearningScore(positives: 3, negatives: 3, missed: 1, falseAlarms: 0)
let baselineErrors = LearningScore(positives: 3, negatives: 3, missed: 0, falseAlarms: 3)
check(!PersonalLearner.canAdopt(candidate: worseMisses, baseline: baselineErrors), "fewer false alarms cannot hide increased misses")
check(!PersonalLearner.canAdopt(candidate: baselineErrors, baseline: baselineErrors), "tied validation results cannot promote")
var tuned = DriftCandidateRule(thresholds: DriftThresholds(heartRateDrop: 0.06, quietSeconds: 120))
var tunedTrial = trial
// Reuse the genuine live-rule fixture, not replay frames, to check runtime threshold wiring.
tunedTrial.startedAt = start
tunedTrial.heart = [heart(20,72), heart(150,72), heart(270,72), heart(400,67), heart(440,67), heart(480,67)]
for half in 0...960 { tuned.addMotion(x: 0, y: 0, z: 1, time: start.timeIntervalSince1970 + Double(half)/2) }
check(tuned.evaluate(trial: tunedTrial, now: start.addingTimeInterval(480)) == "candidate", "adopted supported thresholds affect runtime candidate evaluation")
check(tuned.latestFeatures?.validSensors == true && tuned.latestFeatures?.heartRateDrop != nil, "runtime records features observed at decision time")
let stateDecoded = try JSONDecoder().decode(LearningState.self, from: JSONEncoder().encode(proposedState))
check(stateDecoded.proposal?.thresholds == proposedState.proposal?.thresholds, "learning state survives persistence")

var warmupTrial = learningTrial(0, sleep: false)
check(PersonalLearner.evaluate(warmupTrial, thresholds: .standard)?.falseAlarm == false,
      "post-baseline sensor warmup does not make every awake trial ineligible")
var shortCoverage = warmupTrial
shortCoverage.featureFrames?.removeAll { $0.time < start.addingTimeInterval(1600) }
check(PersonalLearner.evaluate(shortCoverage, thresholds: .standard) == nil,
      "brief observed awake coverage is not counted as a successful silent trial")
var uncertainGap = warmupTrial
uncertainGap.featureFrames?.removeAll { $0.time > start.addingTimeInterval(1000) && $0.time < start.addingTimeInterval(1100) }
check(PersonalLearner.evaluate(uncertainGap, thresholds: .standard) == nil,
      "missing data inside the evaluated interval excludes a silent no-alert result")
var tiedFuture = futureTrials
for index in tiedFuture.indices where tiedFuture[index].estimatedSleepAt != nil {
    let trialStart = tiedFuture[index].startedAt
    let existingFrames = tiedFuture[index].featureFrames
    tiedFuture[index].featureFrames = existingFrames?.map { original in
        var frame = original
        if frame.time.timeIntervalSince(trialStart) >= 900 { frame.heartRateDrop = 0.10 }
        return frame
    }
}
let rejected = PersonalLearner.refreshed(proposedState, trials: trainingTrials + tiedFuture,
    now: trainedAt.addingTimeInterval(10 * 86400))
check(rejected.proposal == nil && rejected.policy.thresholds == .standard,
      "candidate with no improvement on later trials is rejected")
