import SwiftUI

struct DriftTrialView: View {
    @State private var monitor = DriftMonitor.shared
    var body: some View {
        List {
            Section {
                Text("Experimental estimate, not confirmed sleep.").font(.headline)
            }
            Section("30-minute trial") {
                Text(monitor.status)
                if monitor.isActive {
                    LabeledContent("Heart samples", value: "\(monitor.heartCount)")
                    LabeledContent("Low movement", value: "\(monitor.quietSeconds) sec")
                    Button("Stop check") { monitor.stop() }
                } else {
                    Button(monitor.starting ? "Starting…" : "Start check") {
                        Task { await monitor.start() }
                    }.disabled(monitor.starting)
                }
                Text("The Watch may continue the check with the screen off for up to 30 minutes. A timed backup is scheduled for minute 30; backup alerts are not counted as detections.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let current = monitor.current {
                    NavigationLink("Review this trial") { TrialReviewView(id: current.id) }
                }
            }
            Section {
                Text("Experimental drift-off check").font(.headline)
                Text("Start while awake and settling into bed. Stay awake for the first 5 minutes to collect a baseline. A heart-rate drop plus sustained low wrist movement may trigger a candidate alert.")
                Text("This is an unvalidated rule, not sleep detection. No fresh heart data means no estimate. It can miss sleep or alert while you're awake.")
                Text("For initial testing, remove your lenses first, then mark the app's status as ‘in’ only as a test flag. Do not rely on the prototype to protect you from sleeping in lenses.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                NavigationLink("Learning settings") { LearningView() }
                Text("For learning, keep a test running after an alert only when practical. Stopping early may leave too little data to compare silent candidate settings. Always remove lenses before test sessions.")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink("Trial results") { TrialHistoryView() }
            }
        }
        .navigationTitle("Drift-off trial")
    }
}
