import SwiftUI

struct PhoneHomeView: View {
    @Environment(LensStore.self) private var store
    @State private var selectedTab: HomeTab = .today

    private enum HomeTab: Hashable { case today, reminders, trials }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                today
                    .navigationTitle("Lenses")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("Lenses").font(.headline).foregroundStyle(PhonePalette.text)
                        }
                    }
            }
            .tabItem { Label("Today", systemImage: "eye") }
            .tag(HomeTab.today)

            NavigationStack {
                CustomRemindersView()
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Reminders", systemImage: "bell") }
            .tag(HomeTab.reminders)

            NavigationStack {
                TrialHistoryView()
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Sleep trial", systemImage: "waveform.path.ecg") }
            .tag(HomeTab.trials)
        }
        .tint(PhonePalette.accent)
        .toolbarBackground(PhonePalette.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
    }

    private var today: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                statusCard
                nightlyCard
                quickReminderCard
                Button { selectedTab = .reminders } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.plus")
                            .foregroundStyle(PhonePalette.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Your own schedule").font(.subheadline.weight(.semibold))
                                .foregroundStyle(PhonePalette.text)
                            Text("Add a one-time or daily reminder")
                                .font(.caption).foregroundStyle(PhonePalette.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold)).foregroundStyle(PhonePalette.secondary)
                    }
                    .frame(minHeight: 44)
                    .padding(16)
                    .background(PhonePalette.surface, in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .lensPhoneSurface()
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: store.lensesAreIn ? "eye.fill" : "checkmark.circle.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(store.lensesAreIn ? PhonePalette.accent : PhonePalette.mint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("LENS CHECK")
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(PhonePalette.secondary)
                    Text(store.lensesAreIn ? "Lenses are in" : "Lenses are out")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(store.lensesAreIn ? PhonePalette.text : PhonePalette.mint)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(store.lensesAreIn ? "Take them out before you sleep." : "Removal logged. You're all set.")
                        .font(.subheadline)
                        .foregroundStyle(PhonePalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Button {
                if store.lensesAreIn { store.markLensesOut() }
                else { store.markLensesIn() }
            } label: {
                Text(store.lensesAreIn ? "I've removed my lenses" : "Put lenses in")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(PhonePalette.background)
                    .background(store.lensesAreIn ? PhonePalette.accent : PhonePalette.mint,
                                in: RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .accessibilityHint(store.lensesAreIn ? "Logs removal and cancels pending follow-up alerts" : "Marks your contact lenses as being worn")
        }
        .padding(20)
        .background(PhonePalette.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(PhonePalette.accent.opacity(0.12), lineWidth: 1)
        }
    }

    private var nightlyCard: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $store.reminderEnabled) {
                Label("Nightly reminder", systemImage: "moon")
                    .font(.subheadline.weight(.semibold))
            }
            .onChange(of: store.reminderEnabled) { store.persistAndReschedule() }
            Divider().overlay(PhonePalette.separator)
            DatePicker("Reminder time", selection: $store.bedtime, displayedComponents: .hourAndMinute)
                .font(.subheadline)
                .datePickerStyle(.compact)
                .onChange(of: store.bedtime) { store.persistAndReschedule() }
            Text(store.reminderEnabled ? "Every day on this iPhone" : "Off · turn on to receive this reminder")
                .font(.caption)
                .foregroundStyle(PhonePalette.secondary)
        }
        .padding(18)
        .background(PhonePalette.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private var quickReminderCard: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 14) {
            Label("Remind me later", systemImage: "timer")
                .font(.subheadline.weight(.semibold))
            Picker("Delay", selection: $store.leadSeconds) {
                ForEach(LensStore.remindInOptions, id: \.self) { seconds in
                    Text(LensStore.durationLabel(seconds)).tag(seconds)
                }
            }
            .font(.subheadline)
            .pickerStyle(.menu)
            .onChange(of: store.leadSeconds) { store.durationDidChange() }
            Button { store.remindInSelectedDelay() } label: {
                Label("Start reminder", systemImage: "bell.badge")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(PhonePalette.accent)
                    .background(PhonePalette.secondaryButton, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            if let message = store.quickReminderMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(PhonePalette.secondary)
            }
        }
        .padding(18)
        .background(PhonePalette.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

#Preview {
    PhoneHomeView()
        .environment(LensStore.shared)
        .preferredColorScheme(.dark)
}
