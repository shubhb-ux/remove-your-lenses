import SwiftUI

struct RemindInPicker: View {
    @Bindable var store: LensStore

    var body: some View {
        Picker("Remind me in", selection: $store.leadSeconds) {
            ForEach(LensStore.remindInOptions, id: \.self) { seconds in
                Text(LensStore.durationLabel(seconds)).tag(seconds)
            }
        }
        .onChange(of: store.leadSeconds) {
            store.durationDidChange()
        }
    }
}

struct ReminderSettingsView: View {
    @Bindable var store: LensStore
    var compact: Bool = false

    var body: some View {
        Group {
            Toggle("Nightly reminder", isOn: $store.reminderEnabled)
                .onChange(of: store.reminderEnabled) {
                    store.persistAndReschedule()
                }

            DatePicker(
                "Reminder time",
                selection: $store.bedtime,
                displayedComponents: .hourAndMinute
            )
            .onChange(of: store.bedtime) {
                store.persistAndReschedule()
            }

            if !compact {
                LabeledContent("Nightly alarm", value: store.reminderTimeText)
            }
        }
    }
}
