import SwiftUI

struct CustomRemindersView: View {
    @State private var reminders = CustomReminders.shared

    var body: some View {
        List {
            Section {
                NavigationLink("Add reminder") { CustomReminderEditor() }
                    .disabled(reminders.reminders.count >= CustomReminders.maximumCount)
            }
            .lensPhoneRows()
            Section("Your reminders") {
                if reminders.reminders.isEmpty {
                    Text("Add a one-time reminder for a nap, or a daily reminder at any time.")
                        .foregroundStyle(.secondary)
                }
                ForEach(reminders.reminders) { reminder in
                    NavigationLink {
                        CustomReminderEditor(reminder: reminder)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reminder.title)
                            Text(reminder.timeDescription).font(.caption).foregroundStyle(.secondary)
                            if !reminder.isEnabled { Text("Off").font(.caption).foregroundStyle(.secondary) }
                            else if !reminder.repeatsDaily && reminder.date < Date() {
                                Text("Past reminder").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .lensPhoneRows()
            Section {
                Text("Reminders are saved on this device. Sound and wrist taps depend on your notification, Silent Mode and Focus settings.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .lensPhoneRows()
        }
        .lensPhoneSurface()
        .navigationTitle("My reminders")
    }
}

private struct CustomReminderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reminder: CustomLensReminder
    @State private var saving = false
    @State private var error: String?
    private let isExisting: Bool

    init(reminder: CustomLensReminder? = nil) {
        isExisting = reminder != nil
        _reminder = State(initialValue: reminder ?? CustomLensReminder())
    }

    var body: some View {
        Form {
            Section {
                TextField("Reminder name", text: $reminder.title)
                Toggle("Enabled", isOn: $reminder.isEnabled)
                Toggle("Repeat every day", isOn: $reminder.repeatsDaily)
                if reminder.repeatsDaily {
                    DatePicker("Time", selection: $reminder.date, displayedComponents: .hourAndMinute)
                } else {
                    DatePicker("Date", selection: $reminder.date, displayedComponents: .date)
                    DatePicker("Time", selection: $reminder.date, displayedComponents: .hourAndMinute)
                }
            }
            .lensPhoneRows()
            Section {
                Button(saving ? "Saving…" : "Save reminder") {
                    saving = true
                    Task { @MainActor in
                        defer { saving = false }
                        // Store notifications at whole minutes and validate that exact fire time.
                        reminder.date = Calendar.current.dateInterval(of: .minute, for: reminder.date)?.start ?? reminder.date
                        do { try await CustomReminders.shared.save(reminder); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }
                .disabled(saving)
                if isExisting {
                    Button("Delete reminder", role: .destructive) {
                        CustomReminders.shared.delete(reminder)
                        dismiss()
                    }.disabled(saving)
                }
            }
            .lensPhoneRows()
        }
        .disabled(saving)
        .lensPhoneSurface()
        .navigationTitle(isExisting ? "Edit reminder" : "New reminder")
        .alert("Reminder not saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}
