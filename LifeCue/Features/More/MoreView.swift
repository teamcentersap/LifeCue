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
    @State private var showPaywall = false
    @EnvironmentObject private var purchases: PurchaseManager

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

                backupRow

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
            .sheet(isPresented: $showPaywall) {
                ProUnlockView()
                    .environmentObject(purchases)
            }
            .navigationDestination(isPresented: $showHelp) {
                HelpView()
            }
            .navigationDestination(isPresented: $openBackupRestore) {
                backupRestoreView
                    .onAppear { notificationNavigation.consumePendingBackupRestore() }
            }
            .onChange(of: notificationNavigation.pendingOpenBackupRestore) { _, pending in
                if pending {
                    if FeatureAccessPolicy.allows(.backup, isPro: purchases.hasProAccess) {
                        openBackupRestore = true
                    } else {
                        notificationNavigation.consumePendingBackupRestore()
                        showPaywall = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var backupRow: some View {
        if FeatureAccessPolicy.allows(.backup, isPro: purchases.hasProAccess) {
            NavigationLink {
                backupRestoreView
            } label: {
                Label("Backup & Restore", systemImage: "externaldrive")
            }
        } else {
            Button {
                showPaywall = true
            } label: {
                Label("Backup & Restore", systemImage: "lock.fill")
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
