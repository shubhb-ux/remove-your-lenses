import SwiftUI

struct TrialHistoryView: View {
    @State private var archive = TrialArchive.shared
    @State private var transfer = TrialTransfer.shared

    var body: some View {
        List {
            #if os(iOS)
            Section {
                Label("Start a check on your Watch", systemImage: "applewatch")
                    .font(.headline)
                Text("Open Reminders → Drift-off trial on your Watch. Review its records here after they transfer.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .lensPhoneRows()
            #endif
            Section {
                NavigationLink { LearningView() } label: {
                    Label("Learn my patterns", systemImage: "sparkles")
                }
            }
            .lensPhoneRows()
            Section("Self-reported results") {
                LabeledContent("Candidate alerts", value: "\(archive.trials.filter { $0.candidateAt != nil }.count)")
                LabeledContent("Marked awake", value: "\(archive.trials.filter { $0.candidateAt != nil && $0.feedback == .awake }.count)")
                LabeledContent("Reported misses", value: "\(archive.trials.filter { $0.selfReportedMiss == true }.count)")
                Text("Unreviewed alerts are not counted as correct. A miss means reported sleep without a candidate alert in the preceding 10 minutes. These labels do not establish actual sleep or accuracy.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .lensPhoneRows()
            Section("Entered EEG references") {
                LabeledContent("References added", value: "\(archive.trials.filter { $0.eegReference != nil }.count)")
                LabeledContent("Onsets evaluated", value: "\(archive.trials.filter { $0.eegMiss != nil }.count)")
                LabeledContent("Missed onsets", value: "\(archive.trials.filter { $0.eegMiss == true }.count)")
                LabeledContent("Alerts evaluated", value: "\(archive.trials.filter { $0.eegFalseAlarm != nil }.count)")
                LabeledContent("False alarms", value: "\(archive.trials.filter { $0.eegFalseAlarm == true }.count)")
                Text("Compared with manually entered, clock-aligned EEG report results, using a 10-minute warning window. Missing coverage is excluded. Reports are not independently verified.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .lensPhoneRows()
            Section("Trials") {
                if archive.trials.isEmpty { Text("No trials yet") }
                ForEach(archive.trials) { trial in
                    NavigationLink {
                        TrialReviewView(id: trial.id)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(trial.startedAt.formatted(date: .abbreviated, time: .shortened))
                            Text(trial.candidateAt == nil ? "No candidate alert" : trial.feedback.title)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .lensPhoneRows()
            if let error = transfer.lastError {
                Text(error).foregroundStyle(.red)
                Button("Retry queued transfers") { transfer.activate() }
            }
            if let error = archive.storageError { Text("Storage: \(error)").foregroundStyle(.red) }
            Section {
                Text("Trial records contain heart-rate data and stay on your devices. Watch records transfer to the paired iPhone when available. Export only if you want to share them.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .lensPhoneRows()
        }
        .lensPhoneSurface()
        .navigationTitle("Trial results")
    }
}

struct TrialReviewView: View {
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var archive = TrialArchive.shared
    @State private var transfer = TrialTransfer.shared
    @State private var sleepDate = Date()
    @State private var confirmDelete = false
    private var trial: DriftTrial? { archive.trials.first { $0.id == id } }

    var body: some View {
        Form {
            if let trial {
                Section("Recorded data") {
                    Text(trial.startedAt.formatted(date: .abbreviated, time: .shortened))
                    Text(trial.endReason)
                    LabeledContent("Heart samples", value: "\(trial.heart.count)")
                    LabeledContent("Motion coverage", value: "\(Int((trial.motion.last?.coverageSeconds ?? 0) / 60)) min")
                    Text("Rule: \(trial.modelVersion)").font(.caption)
                    if let alert = trial.candidateAt { Text("Candidate: \(alert.formatted(date: .omitted, time: .standard))") }
                    if let backup = trial.backupAt { Text("Timed backup: \(backup.formatted(date: .omitted, time: .standard))") }
                }
                .lensPhoneRows()
                if trial.candidateAt != nil {
                    Section("At the candidate alert") {
                        Picker("How did you feel?", selection: Binding(get: { self.trial?.feedback ?? .unreviewed }, set: { archive.label(id, feedback: $0) })) {
                            ForEach(TrialAlertFeedback.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                    .lensPhoneRows()
                }
                if let end = trial.endedAt, end > trial.startedAt {
                    Section("Whole-trial outcome") {
                        Toggle("I stayed awake throughout", isOn: Binding(get: { self.trial?.stayedAwakeThroughout == true },
                            set: { archive.recordStayedAwake(id, awake: $0) }))
                        Text("Select only if you stayed awake for the entire trial. Selecting it clears an estimated sleep time; saving a sleep time clears this answer. Aligned EEG results take priority for learning.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .lensPhoneRows()
                    Section("Estimated sleep onset") {
                        Text("Optional: enter your best estimate after the trial. It is not a measured sleep time.")
                            .font(.footnote)
                        DatePicker("Date", selection: $sleepDate, in: trial.startedAt...end, displayedComponents: .date)
                        DatePicker("Time", selection: $sleepDate, in: trial.startedAt...end, displayedComponents: .hourAndMinute)
                        Button("Save estimated sleep time") { archive.recordSleep(id, at: sleepDate) }
                        if let date = trial.estimatedSleepAt {
                            Text("Reported: \(date.formatted(date: .omitted, time: .standard))")
                            if let lead = trial.warningSeconds { Text("Warning lead: \(Int(lead)) seconds (negative means late)") }
                            Button("Clear sleep estimate") { archive.recordSleep(id, at: nil) }
                        }
                    }
                    .lensPhoneRows()
                }
                Section("EEG sleep reference") {
                    if let reference = trial.eegReference {
                        Text(reference.source).font(.headline)
                        Text(reference.alignmentConfirmed ? "Clock alignment confirmed by you" : "Clock alignment unconfirmed · excluded from comparisons")
                            .font(.caption).foregroundStyle(.secondary)
                        if let onset = reference.sleepOnset {
                            Text("Reported EEG onset: \(onset.formatted(date: .abbreviated, time: .standard))")
                        } else { Text("Reported awake throughout the EEG recording") }
                        if let lead = trial.eegWarningSeconds {
                            Text("EEG warning lead: \(Int(lead)) seconds (negative means late)")
                        }
                        if let missed = trial.eegMiss {
                            Text(missed ? "No advance warning in the 10-minute window" : "Candidate warning in the 10-minute window")
                        }
                        if let falseAlarm = trial.eegFalseAlarm {
                            Text(falseAlarm ? "False alarm against entered EEG reference" : "Sleep onset follows within 10 minutes")
                        }
                    } else {
                        Text("Attach scored sleep times from an EEG report. Keep these separate from your own sleep estimates.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    #if os(iOS)
                    NavigationLink(trial.eegReference == nil ? "Add EEG reference" : "Edit EEG reference") {
                        EEGReferenceEditor(trial: trial)
                    }.disabled(trial.endedAt == nil)
                    #else
                    Text("Add or edit EEG report results in the paired iPhone app.").font(.footnote)
                    #endif
                }
                .lensPhoneRows()
                Section {
                    #if os(iOS)
                    ShareLink(item: archive.url(for: trial)) { Text("Export trial JSON") }
                    #else
                    Text("Open this trial on the paired iPhone to export its JSON.").font(.footnote)
                    Button("Send to iPhone again") { TrialTransfer.shared.send(archive.url(for: trial)) }
                        .disabled(trial.endedAt == nil)
                    #endif
                    Button("Delete local trial", role: .destructive) { confirmDelete = true }
                        .disabled(trial.endedAt == nil)
                }
                .lensPhoneRows()
            }
        }
        .overlay(alignment: .bottom) {
            if let error = archive.storageError ?? transfer.lastError {
                Text(error).font(.footnote).padding().background(.regularMaterial)
            }
        }
        .lensPhoneSurface()
        .navigationTitle("Review trial")
        .onAppear {
            if let trial { sleepDate = trial.estimatedSleepAt ?? trial.endedAt ?? trial.startedAt }
        }
        .confirmationDialog("Delete this trial from this device? Copies on other devices or previously exported files remain.", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let trial { archive.delete(trial) }; dismiss()
            }
        }
    }
}
