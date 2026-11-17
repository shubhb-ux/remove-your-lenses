#if os(iOS)
import SwiftUI

struct EEGReferenceEditor: View {
    let trialID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var archive = TrialArchive.shared
    @State private var source: String
    @State private var recordingStart: Date
    @State private var recordingEnd: Date
    @State private var onset: Date
    @State private var outcome: EEGSleepReference.Outcome
    @State private var timeZoneIdentifier: String
    @State private var aligned: Bool
    @State private var notes: String
    @State private var error: String?
    @State private var confirmRemove = false
    private var trial: DriftTrial? { archive.trials.first { $0.id == trialID } }
    private var reportZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    init(trial: DriftTrial) {
        trialID = trial.id
        let reference = trial.eegReference
        _source = State(initialValue: reference?.source ?? "")
        _recordingStart = State(initialValue: reference?.recordingStart ?? trial.startedAt)
        _recordingEnd = State(initialValue: reference?.recordingEnd ?? trial.endedAt ?? Date())
        _onset = State(initialValue: reference?.sleepOnset ?? trial.estimatedSleepAt ?? trial.startedAt)
        _outcome = State(initialValue: reference?.outcome ?? .sleepOnset)
        _timeZoneIdentifier = State(initialValue: reference?.timeZoneIdentifier ?? TimeZone.current.identifier)
        _aligned = State(initialValue: reference?.alignmentConfirmed ?? false)
        _notes = State(initialValue: reference?.notes ?? "")
    }

    var body: some View {
        Form {
            Section {
                Text("Enter scored results from an EEG report or EEG device. This does not record EEG, interpret raw waveforms, or verify the report.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }.lensPhoneRows()
            Section("Report details") {
                TextField("EEG report or device name", text: $source)
                Picker("Report time zone", selection: $timeZoneIdentifier) {
                    ForEach(Array(Set(TimeZone.knownTimeZoneIdentifiers + [timeZoneIdentifier, "UTC"])).sorted(), id: \.self) { zone in
                        Text(zone.replacingOccurrences(of: "_", with: " ")).tag(zone)
                    }
                }
                .pickerStyle(.navigationLink)
            }.lensPhoneRows()
            Section {
                DatePicker("Recording start", selection: $recordingStart)
                secondsControl("Start seconds", selection: $recordingStart)
                DatePicker("Recording end", selection: $recordingEnd)
                secondsControl("End seconds", selection: $recordingEnd)
            } header: { Text("EEG recording period") } footer: {
                Text("Times are displayed in \(timeZoneIdentifier). Enter the actual recording period, including any portion before or after this trial.")
            }.lensPhoneRows()
            Section {
                Picker("EEG result", selection: $outcome) {
                    ForEach(EEGSleepReference.Outcome.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if outcome == .sleepOnset {
                    DatePicker("First sleep onset", selection: $onset)
                    secondsControl("Onset seconds", selection: $onset)
                    Text("Use the first EEG-scored sleep onset in this recording, not a bedtime or your own estimate.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                TextField("Notes (optional)", text: $notes, axis: .vertical)
            }.lensPhoneRows()
            Section {
                Toggle("I checked clock alignment", isOn: $aligned)
                Text("Confirm that the report times line up with the Watch trial. Correct any clock difference before entering times. Unconfirmed references are saved but excluded from EEG comparisons.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.lensPhoneRows()
            if let trial, let end = trial.endedAt {
                Section("Watch trial, in report time zone") {
                    Text(reportDate(trial.startedAt))
                    Text("to \(reportDate(end))")
                }.lensPhoneRows()
            }
            Section {
                Button("Save EEG reference") { save() }
                    .disabled(trial?.endedAt == nil)
                if trial?.eegReference != nil {
                    Button("Remove EEG reference", role: .destructive) { confirmRemove = true }
                }
            }.lensPhoneRows()
        }
        .environment(\.timeZone, reportZone)
        .lensPhoneSurface()
        .navigationTitle("EEG reference")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove this trial's EEG reference?", isPresented: $confirmRemove) {
            Button("Remove reference", role: .destructive) {
                do { try archive.recordEEG(trialID, reference: nil); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        }
        .alert("EEG reference not saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func reportDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = reportZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func secondsControl(_ title: String, selection: Binding<Date>) -> some View {
        var calendar = Calendar.current
        calendar.timeZone = reportZone
        return Stepper(value: Binding(get: { calendar.component(.second, from: selection.wrappedValue) }, set: { second in
            if let date = calendar.date(bySetting: .second, value: second, of: selection.wrappedValue) {
                selection.wrappedValue = date
            }
        }), in: 0...59) {
            Text("\(title): \(calendar.component(.second, from: selection.wrappedValue))")
                .font(.subheadline)
        }
    }

    private func save() {
        let reference = EEGSleepReference(source: source.trimmingCharacters(in: .whitespacesAndNewlines),
            recordingStart: recordingStart, recordingEnd: recordingEnd, outcome: outcome,
            sleepOnset: outcome == .sleepOnset ? onset : nil,
            timeZoneIdentifier: timeZoneIdentifier, alignmentConfirmed: aligned, notes: notes)
        do { try archive.recordEEG(trialID, reference: reference); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
#endif
