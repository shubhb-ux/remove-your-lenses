import SwiftUI
import UserNotifications
import UIKit

@main
struct RemoveLensesApp: App {
    @State private var store = LensStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(PhonePalette.background)
        navigation.titleTextAttributes = [.foregroundColor: UIColor(PhonePalette.text)]
        navigation.largeTitleTextAttributes = [.foregroundColor: UIColor(PhonePalette.text)]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UNUserNotificationCenter.current().delegate = AppNotifications.delegate
    }

    var body: some Scene {
        WindowGroup {
            PhoneHomeView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(PhonePalette.accent)
                .foregroundStyle(PhonePalette.text)
                .task {
                    TrialTransfer.shared.activate()
                    LearningCoordinator.shared.refresh(using: TrialArchive.shared.trials)
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
