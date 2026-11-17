import SwiftUI
import UserNotifications
import WatchKit

@main
struct RemoveLensesWatchApp: App {
    @WKApplicationDelegateAdaptor(DriftWatchDelegate.self) var watchDelegate
    @State private var store = LensStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = AppNotifications.delegate
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(store)
                .task {
                    TrialTransfer.shared.activate()
                    ReminderScheduler.shared.registerCategories()
                    _ = await ReminderScheduler.shared.requestPermission()
                    await ReminderScheduler.shared.reschedule(using: store)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { TrialTransfer.shared.activate() }
                }
        }
    }
}
