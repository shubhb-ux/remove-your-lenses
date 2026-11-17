import Foundation

/// Manually transcribed scored EEG results, not raw EEG or independently verified labels.
struct EEGSleepReference: Codable, Equatable {
    enum Outcome: String, Codable, CaseIterable {
        case sleepOnset, awakeThroughout
        var title: String { self == .sleepOnset ? "Sleep onset recorded" : "Awake throughout recording" }
    }
    var source: String
    var recordingStart: Date
    var recordingEnd: Date
    var outcome: Outcome
    var sleepOnset: Date?
    var timeZoneIdentifier: String
    var alignmentConfirmed: Bool
    var notes: String = ""
    var enteredAt = Date()

    func validationError(for trial: DriftTrial) -> String? {
        guard let trialEnd = trial.endedAt else { return "Finish the trial before attaching EEG results." }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Enter the EEG report or device name."
        }
        guard TimeZone(identifier: timeZoneIdentifier) != nil else { return "Select a valid report time zone." }
        guard recordingStart < recordingEnd else { return "Recording end must be after its start." }
        guard recordingStart < trialEnd, recordingEnd > trial.startedAt else {
            return "The EEG recording must overlap this Watch trial."
        }
        if outcome == .sleepOnset {
            guard let sleepOnset, sleepOnset >= recordingStart, sleepOnset <= recordingEnd else {
                return "Sleep onset must fall inside the EEG recording period."
            }
        } else if sleepOnset != nil {
            return "An awake-throughout recording cannot also have a sleep-onset time."
        }
        return nil
    }
}

struct EEGReferenceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension DriftTrial {
    private var alignedEEG: EEGSleepReference? {
        guard let eegReference, eegReference.alignmentConfirmed,
              eegReference.validationError(for: self) == nil else { return nil }
        return eegReference
    }

    var eegWarningSeconds: TimeInterval? {
        guard let reference = alignedEEG, let onset = reference.sleepOnset,
              let end = endedAt, onset >= startedAt, onset <= end,
              let candidateAt, candidateAt >= startedAt, candidateAt <= end else { return nil }
        return onset.timeIntervalSince(candidateAt)
    }

    /// Matches the prototype's existing ten-minute advance-warning evaluation window.
    var eegMiss: Bool? {
        guard let reference = alignedEEG, reference.outcome == .sleepOnset,
              let onset = reference.sleepOnset, let end = endedAt,
              onset >= startedAt, onset <= end else { return nil }
        guard let candidateAt, candidateAt >= startedAt, candidateAt <= end else { return true }
        return !(0...600).contains(onset.timeIntervalSince(candidateAt))
    }

    /// Only classify an alert when the report establishes the following ten minutes.
    /// Missing coverage and alerts after first onset are unknown, not false alarms.
    var eegFalseAlarm: Bool? {
        guard let reference = alignedEEG, let candidateAt, let end = endedAt,
              candidateAt >= startedAt, candidateAt <= end,
              reference.recordingStart <= candidateAt,
              reference.recordingEnd >= candidateAt.addingTimeInterval(600) else { return nil }
        if reference.outcome == .awakeThroughout { return true }
        guard let onset = reference.sleepOnset, onset >= candidateAt else { return nil }
        return onset.timeIntervalSince(candidateAt) > 600
    }
}
