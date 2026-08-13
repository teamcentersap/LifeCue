import SwiftUI

struct RootView: View {
    @Bindable var listViewModel: ReminderListViewModel
    let reminderService: ReminderService
    let personService: PersonService
    let contextService: ContextService
    let organizationDeletionService: OrganizationDeletionService
    let calendarService: CalendarServing
    let ocrService: OCRServing
    let textExtractor: ReminderTextExtracting
    let backupExportService: BackupExportServing
    let backupImportService: BackupImportServing
    let backupReminderScheduler: BackupReminderScheduler
    let notificationScheduler: NotificationScheduling
    @Bindable var notificationNavigation: NotificationNavigationStore

    @State private var showAddSomething = false
    @State private var selectedTab = 0
    @State private var dataRefreshToken = UUID()

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                viewModel: listViewModel,
                reminderService: reminderService,
                personService: personService,
                contextService: contextService,
                notificationNavigation: notificationNavigation,
                onAdd: { showAddSomething = true }
            )
            .tabItem { Label("Home", systemImage: "house") }
            .tag(0)

            CalendarMonthView(
                calendarService: calendarService,
                reminderService: reminderService,
                personService: personService,
                contextService: contextService,
                dataRefreshToken: dataRefreshToken
            )
            .tabItem { Label("Calendar", systemImage: "calendar") }
            .tag(1)

            NavigationStack {
                PeopleListView(
                    personService: personService,
                    contextService: contextService,
                    reminderService: reminderService,
                    organizationDeletionService: organizationDeletionService,
                    onDataChanged: { listViewModel.load() }
                )
            }
            .tabItem { Label("People", systemImage: "person.2") }
            .tag(2)

            MoreView(
                personService: personService,
                contextService: contextService,
                reminderService: reminderService,
                organizationDeletionService: organizationDeletionService,
                backupExportService: backupExportService,
                backupImportService: backupImportService,
                backupReminderScheduler: backupReminderScheduler,
                notificationScheduler: notificationScheduler,
                notificationNavigation: notificationNavigation,
                onBackupDataChanged: {
                    listViewModel.load()
                    dataRefreshToken = UUID()
                },
                onOrganizationDataChanged: { listViewModel.load() }
            )
            .tabItem { Label("More", systemImage: "ellipsis.circle") }
            .tag(3)
        }
        .tint(LifeCueTheme.today)
        .onChange(of: notificationNavigation.pendingGeneration) { _, _ in
            if notificationNavigation.pendingOpenBackupRestore {
                selectedTab = 3
            } else {
                selectedTab = 0
            }
        }
        .sheet(isPresented: $showAddSomething) {
            AddSomethingView(
                reminderService: reminderService,
                personService: personService,
                contextService: contextService,
                calendarService: calendarService,
                ocrService: ocrService,
                textExtractor: textExtractor,
                onReminderSaved: {
                    showAddSomething = false
                    listViewModel.load()
                },
                onCancel: { showAddSomething = false }
            )
        }
    }
}
