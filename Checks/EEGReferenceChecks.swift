
var eegTrial = DriftTrial(startedAt: start)
eegTrial.endedAt = start.addingTimeInterval(1800)
eegTrial.candidateAt = start.addingTimeInterval(480)
var reference = EEGSleepReference(source: "Scored EEG report", recordingStart: start,
    recordingEnd: start.addingTimeInterval(1800), outcome: .sleepOnset,
    sleepOnset: start.addingTimeInterval(600), timeZoneIdentifier: "Europe/London", alignmentConfirmed: true)
eegTrial.eegReference = reference
check(reference.validationError(for: eegTrial) == nil, "aligned EEG report validates")
check(eegTrial.eegMiss == false && eegTrial.eegWarningSeconds == 120, "EEG onset produces correct advance-warning lead")
check(eegTrial.eegFalseAlarm == false, "sleep within warning window is not classified as a false alarm")
check(eegTrial.estimatedSleepAt == nil && eegTrial.selfReportedMiss == nil, "EEG references do not overwrite self-reported estimates")
eegTrial.eegReference?.alignmentConfirmed = false
check(eegTrial.eegMiss == nil && eegTrial.eegFalseAlarm == nil && eegTrial.eegWarningSeconds == nil, "unaligned EEG reference is excluded")
eegTrial.eegReference = reference
eegTrial.candidateAt = nil
check(eegTrial.eegMiss == true && eegTrial.eegFalseAlarm == nil, "EEG sleep without a candidate is a miss, not an evaluated alert")
eegTrial.candidateAt = start.addingTimeInterval(650)
check(eegTrial.eegMiss == true && eegTrial.eegWarningSeconds == -50, "EEG detects late candidate and negative lead")
check(eegTrial.eegFalseAlarm == nil, "already-asleep alert is not guessed to be an awake false alarm")
eegTrial.candidateAt = start.addingTimeInterval(480)
reference.outcome = .awakeThroughout; reference.sleepOnset = nil
eegTrial.eegReference = reference
check(eegTrial.eegFalseAlarm == true && eegTrial.eegMiss == nil, "awake-throughout EEG supports a false alarm, not a missed onset")
reference.recordingEnd = start.addingTimeInterval(500); eegTrial.eegReference = reference
check(eegTrial.eegFalseAlarm == nil, "partial EEG coverage cannot establish ten-minute false alarm")
reference.recordingStart = start.addingTimeInterval(490)
check(reference.validationError(for: eegTrial) == nil, "partially overlapping EEG recording may be attached")
eegTrial.eegReference = reference
check(eegTrial.eegFalseAlarm == nil, "EEG beginning after candidate does not classify that candidate")
reference.recordingStart = start.addingTimeInterval(2000); reference.recordingEnd = start.addingTimeInterval(2100)
check(reference.validationError(for: eegTrial) != nil, "nonoverlapping EEG recording rejected")
reference.recordingStart = start; reference.recordingEnd = start
check(reference.validationError(for: eegTrial) != nil, "zero-length EEG recording rejected")
reference.recordingEnd = start.addingTimeInterval(1800)
reference.source = "  "
check(reference.validationError(for: eegTrial) != nil, "EEG provenance source is required")
reference.source = "EEG report"; reference.timeZoneIdentifier = "not-a-zone"
check(reference.validationError(for: eegTrial) != nil, "invalid EEG time zone rejected")
reference.timeZoneIdentifier = "Asia/Kolkata"; reference.outcome = .sleepOnset
reference.sleepOnset = start.addingTimeInterval(1900)
check(reference.validationError(for: eegTrial) != nil, "sleep onset outside EEG recording rejected")
reference.sleepOnset = start.addingTimeInterval(600)
eegTrial.eegReference = reference
check(eegTrial.eegWarningSeconds == 120, "reference time-zone metadata does not shift absolute timestamps")
var activeTrial = eegTrial; activeTrial.endedAt = nil
check(reference.validationError(for: activeTrial) != nil, "running trials cannot receive EEG references")
let eegDecoded = try JSONDecoder().decode(DriftTrial.self, from: JSONEncoder().encode(eegTrial))
check(eegDecoded.eegReference == eegTrial.eegReference, "EEG source, alignment, timezone, and times round-trip in export")
var oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(eegTrial)) as! [String: Any]
oldJSON.removeValue(forKey: "eegReference"); oldJSON.removeValue(forKey: "eegUpdatedAt")
let oldTrial = try JSONDecoder().decode(DriftTrial.self, from: JSONSerialization.data(withJSONObject: oldJSON))
check(oldTrial.eegReference == nil, "older trial files load without EEG fields")
var localEEG = eegTrial; localEEG.eegUpdatedAt = start.addingTimeInterval(2100)
var beforeEEG = eegTrial; beforeEEG.eegReference = nil; beforeEEG.eegUpdatedAt = nil
check(TrialMerge.merge(local: localEEG, incoming: beforeEEG).eegReference == reference, "stale sync cannot erase an EEG reference")
var removedEEG = localEEG; removedEEG.eegReference = nil
removedEEG.eegUpdatedAt = start.addingTimeInterval(2200)
check(TrialMerge.merge(local: localEEG, incoming: removedEEG).eegReference == nil, "removing EEG reference syncs with its own revision")
var newSensorData = beforeEEG; newSensorData.dataUpdatedAt = start.addingTimeInterval(2300)
check(TrialMerge.merge(local: localEEG, incoming: newSensorData).eegReference == reference, "new sensor snapshots preserve independent EEG annotations")
