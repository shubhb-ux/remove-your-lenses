import Foundation
import Observation
import UserNotifications

struct CustomLensReminder: Identifiable, Codable {
    var id = UUID()
    var title = "Remove contact lenses"
    var date = Date().addingTimeInterval(15 * 60)
    var repeatsDaily = false
    var isEnabled = true

    var notificationID: String { "custom-lens-\(id.uuidString)" }
    var timeDescription: String {
        repeatsDaily ? "Every day at \(date.formatted(date: .omitted, time: .shortened))"
            : date.formatted(date: .abbreviated, time: .shortened)
    }
}

@MainActor @Observable
final class CustomReminders {
    static let shared = CustomReminders()
    static let maximumCount = 20
    private(set) var reminders: [CustomLensReminder]
    private let key = "customLensReminders.v1"

    private init() {
        reminders = (UserDefaults.standard.data(forKey: "customLensReminders.v1")
            .flatMap { try? JSONDecoder().decode([CustomLensReminder].self, from: $0) }) ?? []
    }

    func save(_ draft: CustomLensReminder) async throws {
        var reminder = draft
        reminder.date = Calendar.current.dateInterval(of: .minute, for: draft.date)?.start ?? draft.date
        reminder.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if reminder.title.isEmpty { reminder.title = "Remove contact lenses" }
        let existing = reminders.contains { $0.id == reminder.id }
        guard existing || reminders.count < Self.maximumCount else {
            throw ReminderError.limitReached
        }
        if reminder.isEnabled {
            guard reminder.repeatsDaily || reminder.date > Date() else { throw ReminderError.pastDate }
            guard await ReminderScheduler.shared.requestPermission() else { throw ReminderError.permissionDenied }
            ReminderScheduler.shared.registerCategories()
            try await UNUserNotificationCenter.current().add(request(for: reminder))
        } else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminder.notificationID])
        }
        if let index = reminders.firstIndex(where: { $0.id == reminder.id }) { reminders[index] = reminder }
        else { reminders.append(reminder) }
        persist()
    }

    func delete(_ reminder: CustomLensReminder) {
        reminders.removeAll { $0.id == reminder.id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminder.notificationID])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [reminder.notificationID])
        persist()
    }

    private func request(for reminder: CustomLensReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Remove contact lenses" : reminder.title
        content.body = "Take out your contact lenses before sleeping."
        content.sound = .default
        content.categoryIdentifier = ReminderAction.category
        content.interruptionLevel = .timeSensitive
        let fields: Set<Calendar.Component> = reminder.repeatsDaily
            ? [.hour, .minute] : [.year, .month, .day, .hour, .minute]
        var components = Calendar.current.dateComponents(fields, from: reminder.date)
        components.second = 0
        return UNNotificationRequest(identifier: reminder.notificationID, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: reminder.repeatsDaily))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(reminders) { UserDefaults.standard.set(data, forKey: key) }
    }

    enum ReminderError: LocalizedError {
        case limitReached, pastDate, permissionDenied
        var errorDescription: String? {
            switch self {
            case .limitReached: return "You can save up to 20 custom reminders. Delete one to add another."
            case .pastDate: return "Choose a time in the future."
            case .permissionDenied: return "Allow notifications in Settings to receive reminders."
            }
        }
    }
}
