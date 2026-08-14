import SwiftUI

struct MoreView: View {
    let personService: PersonService
    let contextService: ContextService
    let reminderService: ReminderService
    let organizationDeletionService: OrganizationDeletionService
    let backupExportService: BackupExportServing
    let backupImportService: BackupImportServing
    let backupReminderScheduler: BackupReminderScheduler
    let notificationScheduler: NotificationScheduling
    @Bindable var notificationNavigation: NotificationNavigationStore
    var onBackupDataChanged: () -> Void = {}
    var onOrganizationDataChanged: () -> Void = {}

    @State private var openBackupRestore = false
    @State private var showHelp = false

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    PeopleListView(
                        personService: personService,
                        contextService: contextService,
                        reminderService: reminderService,
                        organizationDeletionService: organizationDeletionService,
                        onDataChanged: onOrganizationDataChanged
                    )
                } label: {
                    Label("People", systemImage: "person.2")
                }

                NavigationLink {
                    ContextsListView(
                        contextService: contextService,
                        personService: personService,
                        reminderService: reminderService,
                        organizationDeletionService: organizationDeletionService,
                        onDataChanged: onOrganizationDataChanged
                    )
                } label: {
                    Label("Contexts", systemImage: "folder")
                }

                NavigationLink {
                    backupRestoreView
                } label: {
                    Label("Backup & Restore", systemImage: "externaldrive")
                }

                NavigationLink {
                    SettingsView(notificationScheduler: notificationScheduler)
                } label: {
                    Label(MoreNavigationPresentation.settingsLabel, systemImage: MoreNavigationPresentation.settingsSystemImage)
                }
            }
            .lifeCueReadableContentWidth()
            .navigationTitle("More")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showHelp = true
                    } label: {
                        Image(systemName: MoreNavigationPresentation.helpToolbarSystemImage)
                    }
                    .accessibilityLabel(MoreNavigationPresentation.helpToolbarAccessibilityLabel)
                }
            }
            .navigationDestination(isPresented: $showHelp) {
                HelpView()
            }
            .navigationDestination(isPresented: $openBackupRestore) {
                backupRestoreView
                    .onAppear { notificationNavigation.consumePendingBackupRestore() }
            }
            .onChange(of: notificationNavigation.pendingOpenBackupRestore) { _, pending in
                if pending { openBackupRestore = true }
            }
        }
    }

    private var backupRestoreView: some View {
        BackupRestoreView(
            viewModel: BackupRestoreViewModel(
                exportService: backupExportService,
                importService: backupImportService,
                backupReminderScheduler: backupReminderScheduler,
                onDataChanged: onBackupDataChanged
            )
        )
    }
}
