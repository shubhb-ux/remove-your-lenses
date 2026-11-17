// Run from the project root (see TRIALS.md for the full command).
// Include PersonalLearning.swift and all EEG/learning checks with this file.
let start = Date(timeIntervalSince1970: 1_000_000)
func heart(_ seconds: Double, _ bpm: Double) -> TrialHeartSample {
    TrialHeartSample(id: UUID(), time: start.addingTimeInterval(seconds), bpm: bpm)
}
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label)
    print("PASS: \(label)")
}
var trial = DriftTrial(startedAt: start)
trial.heart = [heart(20, 72), heart(150, 72), heart(270, 72), heart(400, 64), heart(440, 64), heart(480, 64)]
var rule = DriftCandidateRule()
for half in 0...960 {
    rule.addMotion(x: 0, y: 0, z: 1, time: start.timeIntervalSince1970 + Double(half) / 2)
}
check(rule.evaluate(trial: trial, now: start.addingTimeInterval(480)) == "candidate", "combined signals can produce a candidate")
var noHeart = trial; noHeart.heart = []
check(rule.evaluate(trial: noHeart, now: start.addingTimeInterval(480)) != "candidate", "stillness alone never triggers")
var noDrop = trial; noDrop.heart = trial.heart.map { var h = $0; h.bpm = 72; return h }
check(rule.evaluate(trial: noDrop, now: start.addingTimeInterval(480)) != "candidate", "no heart-rate drop means no candidate")
check(rule.evaluate(trial: trial, now: start.addingTimeInterval(700)) != "candidate", "stale heart rate or motion cannot trigger")
var sparse = trial; sparse.heart.removeAll { $0.time == start.addingTimeInterval(440) }
check(rule.evaluate(trial: sparse, now: start.addingTimeInterval(480)) != "candidate", "sparse recent heart data rejected")
var moving = rule
moving.addMotion(x: 0.6, y: 0, z: 0.8, time: start.timeIntervalSince1970 + 480.5)
check(moving.evaluate(trial: trial, now: start.addingTimeInterval(480.5)) != "candidate", "wrist movement clears the motion evidence")
var gap = rule
gap.addMotion(x: 0, y: 0, z: 1, time: start.timeIntervalSince1970 + 490)
check(gap.quietSeconds == 0, "sensor gaps reset continuous stillness")
var offWrist = DriftCandidateRule()
for second in 0...500 { offWrist.addMotion(x: 0, y: 0, z: 0, time: start.timeIntervalSince1970 + Double(second)) }
check(offWrist.evaluate(trial: trial, now: start.addingTimeInterval(500)) != "candidate", "zero acceleration is invalid, not quiet evidence")
trial.endedAt = start.addingTimeInterval(1800)
check(trial.selfReportedMiss == nil, "unlabelled trial is excluded from miss counts")
trial.estimatedSleepAt = start.addingTimeInterval(600)
check(trial.selfReportedMiss == true, "reported sleep without a candidate counts as a reported miss")
trial.candidateAt = start.addingTimeInterval(480)
check(trial.selfReportedMiss == false && trial.warningSeconds == 120, "warning lead time is derived from reported onset")
trial.candidateAt = start.addingTimeInterval(650)
check(trial.selfReportedMiss == true, "late alert does not count as an advance warning")
trial.estimatedSleepAt = start.addingTimeInterval(1900)
check(trial.selfReportedMiss == nil, "sleep outside monitored interval is not evaluated")
let decoded = try JSONDecoder().decode(DriftTrial.self, from: JSONEncoder().encode(trial))
check(decoded.id == trial.id && decoded.heart.count == trial.heart.count, "export preserves trial identity and sensor samples")

// Reordered Watch/iPhone transfers must not roll back sensor records or outcome edits.
var collected = DriftTrial(startedAt: start)
collected.endedAt = start.addingTimeInterval(1800)
collected.heart = [heart(20, 72), heart(150, 70)]
collected.dataUpdatedAt = start.addingTimeInterval(1801)
var reviewed = collected
reviewed.feedback = .awake
reviewed.feedbackUpdatedAt = start.addingTimeInterval(1900)
reviewed.estimatedSleepAt = start.addingTimeInterval(600)
reviewed.sleepUpdatedAt = start.addingTimeInterval(1900)
var stale = collected
stale.endedAt = nil
stale.heart = []
stale.dataUpdatedAt = start.addingTimeInterval(900)
let retained = TrialMerge.merge(local: reviewed, incoming: stale)
check(retained.heart.count == 2 && retained.endedAt == collected.endedAt, "delayed transfer cannot roll back completed sensor data")
check(retained.feedback == .awake && retained.estimatedSleepAt == reviewed.estimatedSleepAt, "delayed transfer cannot erase newer labels")
var cleared = reviewed
cleared.feedback = .unreviewed
cleared.feedbackUpdatedAt = start.addingTimeInterval(2000)
cleared.estimatedSleepAt = nil
cleared.sleepUpdatedAt = start.addingTimeInterval(2000)
let latest = TrialMerge.merge(local: reviewed, incoming: cleared)
check(latest.feedback == .unreviewed && latest.estimatedSleepAt == nil, "explicitly clearing a review syncs correctly")
var freshCollection = collected
freshCollection.heart.append(heart(400, 64))
freshCollection.dataUpdatedAt = start.addingTimeInterval(2100)
let combined = TrialMerge.merge(local: reviewed, incoming: freshCollection)
check(combined.heart.count == 3 && combined.feedback == .awake, "new sensor records preserve independent outcome edits")
check(TrialMerge.merge(local: reviewed, incoming: freshCollection).feedback == TrialMerge.merge(local: freshCollection, incoming: reviewed).feedback, "merge order does not affect independently timestamped reviews")
