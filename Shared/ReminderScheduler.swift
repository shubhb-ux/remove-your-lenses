import Foundation
import UserNotifications

enum ReminderAction {
    static let tookThemOut = "TOOK_THEM_OUT"
    static let snooze = "SNOOZE_10"
    static let category = "LENS_REMINDER"
}

@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    static let nightlyIdentifier = "nightly-lens-reminder"
    static let snoozeIdentifier = "snooze-lens-reminder"

    private let center = UNUserNotificationCenter.current()
    private let nightlyQueue = ReminderWorkQueue()
    private let quickQueue = ReminderWorkQueue()
    private var nightlyRevision = 0
    private var quickRevision = 0
    private var quickRequested = false
    private(set) var lastError: String?

    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func registerCategories() {
        let tookOut = UNNotificationAction(
            identifier: ReminderAction.tookThemOut,
            title: "I took them out",
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: ReminderAction.snooze,
            title: "Remind me in \(LensStore.shared.remindInText)",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: ReminderAction.category,
            actions: [tookOut, snooze],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func reschedule(using store: LensStore) async {
        nightlyRevision += 1
        let revision = nightlyRevision
        let enabled = store.reminderEnabled
        let hour = store.bedtimeHour, minute = store.bedtimeMinute
        let bedtimeText = store.bedtimeText
        let work = nightlyQueue.enqueue {
            guard revision == self.nightlyRevision else { return }
            if !enabled {
                self.center.removePendingNotificationRequests(withIdentifiers: [Self.nightlyIdentifier])
                return
            }
            guard await self.requestPermission(), revision == self.nightlyRevision else { return }
            self.registerCategories()
            let content = self.makeContent(body: "Take out your contacts before you sleep. Bedtime is \(bedtimeText).")
            let request = UNNotificationRequest(identifier: Self.nightlyIdentifier, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true))
            do { try await self.center.add(request); self.lastError = nil }
            catch { self.lastError = error.localizedDescription }
        }
        await work.value
    }

    func snooze(seconds: Int) async {
        #if os(watchOS)
        // End the system smart-alarm session so its repeating taps do not continue through snooze.
        DriftMonitor.shared.stop()
        #endif
        cancelTrialAlerts()
        _ = await remindIn(seconds: seconds)
    }

    func updatePendingRemindIn(seconds: Int) async {
        quickRevision += 1
        let revision = quickRevision
        let work = quickQueue.enqueue {
            guard revision == self.quickRevision else { return }
            let pending = await self.center.pendingNotificationRequests()
            guard revision == self.quickRevision,
                  self.quickRequested || pending.contains(where: { $0.identifier == Self.snoozeIdentifier }) else { return }
            self.quickRequested = true
            _ = await self.installQuickReminder(seconds: seconds, revision: revision)
        }
        await work.value
    }

    @discardableResult
    func remindIn(seconds: Int) async -> Bool {
        quickRevision += 1
        let revision = quickRevision
        quickRequested = true
        var installed = false
        let work = quickQueue.enqueue {
            guard revision == self.quickRevision else { return }
            installed = await self.installQuickReminder(seconds: seconds, revision: revision)
        }
        await work.value
        return installed && revision == quickRevision
    }

    private func installQuickReminder(seconds: Int, revision: Int) async -> Bool {
        guard await requestPermission() else {
            if revision == quickRevision {
                lastError = "Allow notifications in Settings to receive reminders."
                quickRequested = false
            }
            return false
        }
        guard revision == quickRevision else { return false }
        registerCategories()
        let delay = max(1, min(LensStore.maxRemindInSeconds, seconds))
        let content = makeContent(body: "Time to remove your lenses. You asked for a reminder after \(LensStore.durationLabel(delay)).")
        do {
            try await center.add(UNNotificationRequest(identifier: Self.snoozeIdentifier, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(delay), repeats: false)))
            lastError = nil
            if revision == quickRevision { quickRequested = false }
            return true
        } catch {
            lastError = error.localizedDescription
            if revision == quickRevision { quickRequested = false }
            return false
        }
    }

    static let trialBackupID = "drift-trial-backup"
    static let trialAlertID = "drift-trial-alert"

    func scheduleTrialBackup() async throws {
        registerCategories()
        let content = makeContent(body: "Timed backup: your drift-off trial is ending. Remove contact lenses before sleeping.")
        try await center.add(UNNotificationRequest(identifier: Self.trialBackupID, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 30 * 60, repeats: false)))
    }
    func cancelTrialAlerts() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.trialBackupID, Self.trialAlertID])
    }
    func sendTrialAlert(candidate: Bool) async {
        let content = makeContent(body: candidate
            ? "Possible drowsiness (experimental estimate). Remove your contact lenses."
            : "Timed backup — not a sleep detection. Remove your contact lenses.")
        try? await center.add(UNNotificationRequest(identifier: Self.trialAlertID, content: content, trigger: nil))
    }

    func cancelRemovalFollowups() {
        cancelTrialAlerts()
        center.removeDeliveredNotifications(withIdentifiers: [Self.trialBackupID, Self.trialAlertID])
        quickRevision += 1
        quickRequested = false
        quickQueue.enqueue {
            self.center.removePendingNotificationRequests(withIdentifiers: [Self.snoozeIdentifier])
            self.center.removeDeliveredNotifications(withIdentifiers: [Self.snoozeIdentifier])
        }
    }

    private func makeContent(body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Contacts still in?"
        content.body = body
        content.sound = .default
        content.categoryIdentifier = ReminderAction.category
        content.interruptionLevel = .timeSensitive
        return content
    }
}

enum AppNotifications {
    static let delegate = NotificationDelegate()
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        switch response.actionIdentifier {
        case ReminderAction.tookThemOut:
            await MainActor.run {
                LensStore.shared.markLensesOut()
            }
        case ReminderAction.snooze:
            await ReminderScheduler.shared.snooze(seconds: LensStore.shared.leadSeconds)
        default:
            break
        }
    }
}
