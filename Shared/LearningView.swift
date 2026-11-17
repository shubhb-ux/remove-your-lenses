import SwiftUI

struct LearningView: View {
    @State private var learner = LearningCoordinator.shared
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                #if os(iOS)
                Toggle("Learn my patterns", isOn: Binding(get: { learner.state.policy.enabled }, set: { learner.setEnabled($0) }))
                #else
                LabeledContent("Personalization", value: learner.state.policy.enabled ? "On" : "Off")
                Text("Manage learning in the paired iPhone app. New settings apply when you start your next trial.")
                    .font(.footnote).foregroundStyle(.secondary)
                #endif
                Text("Fits personal heart-rate and low-movement thresholds from reviewed trials. This is experimental tuning, not a validated sleep model.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }.lensPhoneRows()
            Section("Progress") {
                Text(learner.state.status)
                LabeledContent("Active heart-rate drop", value: "\(Int((learner.effectiveThresholds.heartRateDrop * 100).rounded()))%")
                LabeledContent("Active low movement", value: "\(Int(learner.effectiveThresholds.quietSeconds)) seconds")
                #if os(iOS)
                LabeledContent("Updates adopted", value: "\(learner.state.adoptedUpdates)")
                #endif
            }.lensPhoneRows()
            #if os(iOS)
            if let proposal = learner.state.proposal {
                Section("Silent candidate") {
                    Text("Candidate settings do not control current alerts.")
                        .font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("Heart-rate drop", value: "\(Int((proposal.thresholds.heartRateDrop * 100).rounded()))%")
                    LabeledContent("Low movement", value: "\(Int(proposal.thresholds.quietSeconds)) seconds")
                    LabeledContent("Training trials", value: "\(proposal.trainingFingerprints.count)")
                    LabeledContent("Later sleep trials", value: "\(learner.state.candidateValidation.positives)/3")
                    LabeledContent("Later awake trials", value: "\(learner.state.candidateValidation.negatives)/3")
                    LabeledContent("Candidate misses", value: "\(learner.state.candidateValidation.missed)")
                    LabeledContent("Current misses", value: "\(learner.state.baselineValidation.missed)")
                    LabeledContent("Candidate false alarms", value: "\(learner.state.candidateValidation.falseAlarms)")
                    LabeledContent("Current false alarms", value: "\(learner.state.baselineValidation.falseAlarms)")
                }.lensPhoneRows()
            }
            Section("How it learns") {
                Text("1. Collect at least 8 usable completed trials, including 2 with sleep onset and 2 with an awake-throughout label.")
                Text("2. Fit a candidate using those trials. Compare it silently against the current rule on new trials started after fitting.")
                Text("3. Adopt only after at least 3 later sleep trials and 3 later awake trials, with fewer errors and no increase in either misses or false alarms.")
                Text("Aligned EEG report results take priority. Otherwise your estimated sleep time or explicit awake-throughout answer is used. Being awake at one alert is not a whole-trial label.")
                Text("Missing or truncated sensor coverage is excluded, not counted as successful. Older recordings lack live feature records and cannot train. The minimum counts are experimental safeguards, not proof of accuracy.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.lensPhoneRows()
            Section {
                Button("Send current settings to Watch") { learner.sendPolicyAgain() }
                Button("Reset learning", role: .destructive) { confirmReset = true }
                Text("Learning stays on your devices. Settings transfer to your Watch and apply at the next trial start, not during a check. Reset turns learning off and restores the standard rule; trial recordings and reviews remain.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.lensPhoneRows()
            #endif
            if let error = learner.storageError { Text(error).foregroundStyle(.red).lensPhoneRows() }
        }
        .lensPhoneSurface()
        .navigationTitle("Learning")
        .onAppear { learner.refresh(using: TrialArchive.shared.trials) }
        .confirmationDialog("Reset learning and restore the standard rule? Trial recordings will remain.", isPresented: $confirmReset) {
            Button("Reset learning", role: .destructive) { learner.reset() }
        }
    }
}
