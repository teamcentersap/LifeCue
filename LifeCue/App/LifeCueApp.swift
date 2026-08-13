import SwiftUI
import SwiftData
import EventKit

@main
struct LifeCueApp: App {
    /// Retained for app lifetime so foreground `willPresent` / tap `didReceive` keep working.
    private let notificationCenterDelegate: LifeCueNotificationCenterDelegate
    private let notificationNavigationStore: NotificationNavigationStore
    private let bootstrap: Result<LifeCueAppComposition, LifeCuePersistenceBootstrapError>
    @AppStorage(LifeCueSettings.appearanceKey) private var appearanceRaw = LifeCueAppearance.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Install before any reminder scheduling / reconcile can deliver a notification.
        let navigationStore = NotificationNavigationStore()
        let notificationDelegate = LifeCueNotificationCenterDelegate(
            navigationStore: navigationStore
        )
        LifeCueNotificationCenterDelegate.install(notificationDelegate)
        self.notificationNavigationStore = navigationStore
        self.notificationCenterDelegate = notificationDelegate
        self.bootstrap = LifeCueAppBootstrap.make()
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrap {
            case .success(let app):
                RootView(
                    listViewModel: app.listViewModel,
                    reminderService: app.reminderService,
                    personService: app.personService,
                    contextService: app.contextService,
                    organizationDeletionService: app.organizationDeletionService,
                    calendarService: app.calendarService,
                    ocrService: app.ocrService,
                    textExtractor: app.textExtractor,
                    backupExportService: app.backupExportService,
                    backupImportService: app.backupImportService,
                    backupReminderScheduler: app.backupReminderScheduler,
                    notificationScheduler: app.notificationScheduler,
                    notificationNavigation: notificationNavigationStore
                )
                .preferredColorScheme(
                    LifeCueAppearance(rawValue: appearanceRaw)?.preferredColorScheme
                )
                .modelContainer(app.container)
                .task {
                    _ = await app.reminderService.reconcileAllNotifications()
                    app.listViewModel.load()
                }
            case .failure:
                PersistenceFailureView()
                    .preferredColorScheme(
                        LifeCueAppearance(rawValue: appearanceRaw)?.preferredColorScheme
                    )
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, case .success(let app) = bootstrap else { return }
            Task { @MainActor in
                _ = await app.reminderService.reconcileAllNotifications()
                app.listViewModel.load()
            }
        }
    }
}
