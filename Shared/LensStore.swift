import Foundation
import SwiftUI

@MainActor @Observable
final class LensStore {
    static let shared = LensStore()

    private enum Key {
        static let reminderEnabled = "reminderEnabled"
        static let bedtimeHour = "bedtimeHour"
        static let bedtimeMinute = "bedtimeMinute"
        static let leadMinutes = "leadMinutes"
        static let leadSeconds = "leadSeconds"
        static let lensesAreIn = "lensesAreIn"
    }

    static let maxRemindInSeconds = 15 * 60
    static let remindInOptions: [Int] = [
        1, 5, 10, 30, 60, 2 * 60, 3 * 60, 5 * 60, 10 * 60, 15 * 60
    ]

    var quickReminderMessage: String?

    @ObservationIgnored private var quickMessageRevision = UUID()

    var reminderEnabled: Bool {
        didSet { UserDefaults.standard.set(reminderEnabled, forKey: Key.reminderEnabled) }
    }

    var bedtimeHour: Int {
        didSet { UserDefaults.standard.set(bedtimeHour, forKey: Key.bedtimeHour) }
    }

    var bedtimeMinute: Int {
        didSet { UserDefaults.standard.set(bedtimeMinute, forKey: Key.bedtimeMinute) }
    }

    var leadSeconds: Int {
        didSet { UserDefaults.standard.set(leadSeconds, forKey: Key.leadSeconds) }
    }

    var lensesAreIn: Bool {
        didSet { UserDefaults.standard.set(lensesAreIn, forKey: Key.lensesAreIn) }
    }

    var bedtime: Date {
        get {
            Calendar.current.date(
                from: DateComponents(hour: bedtimeHour, minute: bedtimeMinute)
            ) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            bedtimeHour = components.hour ?? 23
            bedtimeMinute = components.minute ?? 0
        }
    }

    var reminderTime: Date { bedtime }

    var reminderTimeText: String {
        bedtime.formatted(date: .omitted, time: .shortened)
    }

    var remindInText: String {
        Self.durationLabel(leadSeconds)
    }

    static func durationLabel(_ seconds: Int) -> String {
        if seconds < 60 {
            return seconds == 1 ? "1 second" : "\(seconds) seconds"
        }
        let minutes = seconds / 60
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    var bedtimeText: String {
        bedtime.formatted(date: .omitted, time: .shortened)
    }

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Key.bedtimeHour) == nil {
            reminderEnabled = true
            bedtimeHour = 23
            bedtimeMinute = 0
            leadSeconds = 1
            lensesAreIn = true
            persistAll()
        } else {
            reminderEnabled = defaults.bool(forKey: Key.reminderEnabled)
            bedtimeHour = defaults.integer(forKey: Key.bedtimeHour)
            bedtimeMinute = defaults.integer(forKey: Key.bedtimeMinute)
            let rawLead: Int
            if defaults.object(forKey: Key.leadSeconds) != nil {
                rawLead = defaults.integer(forKey: Key.leadSeconds)
            } else {
                rawLead = defaults.integer(forKey: Key.leadMinutes) * 60
            }
            let clamped = min(max(rawLead, 1), Self.maxRemindInSeconds)
            leadSeconds = Self.remindInOptions.min(by: { abs($0 - clamped) < abs($1 - clamped) }) ?? clamped
            lensesAreIn = defaults.object(forKey: Key.lensesAreIn) as? Bool ?? true
        }
    }

    func markLensesOut() {
        lensesAreIn = false
        quickMessageRevision = UUID()
        quickReminderMessage = nil
        #if os(watchOS)
        DriftMonitor.shared.lensesRemoved()
        #endif
        ReminderScheduler.shared.cancelRemovalFollowups()
        Task { await ReminderScheduler.shared.reschedule(using: self) }
    }

    func markLensesIn() {
        lensesAreIn = true
        Task { await ReminderScheduler.shared.reschedule(using: self) }
    }

    func persistAndReschedule() {
        persistAll()
        Task { await ReminderScheduler.shared.reschedule(using: self) }
    }

    func durationDidChange() {
        persistAll()
        Task { await ReminderScheduler.shared.updatePendingRemindIn(seconds: leadSeconds) }
    }

    func remindInSelectedDelay() {
        persistAll()
        let revision = UUID()
        quickMessageRevision = revision
        let seconds = leadSeconds
        quickReminderMessage = "Scheduling reminder…"
        Task {
            let success = await ReminderScheduler.shared.remindIn(seconds: seconds)
            guard quickMessageRevision == revision else { return }
            quickReminderMessage = success ? "Reminder set for \(Self.durationLabel(seconds))."
                : (ReminderScheduler.shared.lastError ?? "Reminder was cancelled or replaced.")
        }
    }

    private func persistAll() {
        let defaults = UserDefaults.standard
        defaults.set(reminderEnabled, forKey: Key.reminderEnabled)
        defaults.set(bedtimeHour, forKey: Key.bedtimeHour)
        defaults.set(bedtimeMinute, forKey: Key.bedtimeMinute)
        defaults.set(leadSeconds, forKey: Key.leadSeconds)
        defaults.set(lensesAreIn, forKey: Key.lensesAreIn)
    }
}
