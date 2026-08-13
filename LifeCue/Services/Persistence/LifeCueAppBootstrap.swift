import Foundation
import SwiftData

enum LifeCuePersistenceBootstrapError: Error, Equatable, Sendable {
    case persistentContainerUnavailable
}

/// Wires the production app graph after persistent storage opens successfully.
@MainActor
struct LifeCueAppComposition {
    let container: ModelContainer
    let reminderService: ReminderService
    let personService: PersonService
    let contextService: ContextService
    let organizationDeletionService: OrganizationDeletionService
    let ocrService: OCRServing
    let textExtractor: ReminderTextExtracting
    let calendarService: CalendarServing
    let backupExportService: BackupExportServing
    let backupImportService: BackupImportServing
    let backupReminderScheduler: BackupReminderScheduler
    let notificationScheduler: NotificationScheduling
    let listViewModel: ReminderListViewModel
}

enum LifeCueAppBootstrap {
    typealias ContainerFactory = () throws -> ModelContainer

    @MainActor
    static func make(
        containerFactory: ContainerFactory = { try LifeCuePersistence.makeContainer() }
    ) -> Result<LifeCueAppComposition, LifeCuePersistenceBootstrapError> {
        let container: ModelContainer
        do {
            container = try containerFactory()
        } catch {
            return .failure(.persistentContainerUnavailable)
        }

        let modelContext = container.mainContext
        let reminderRepository = SwiftDataReminderRepository(modelContext: modelContext)
        let personRepository = SwiftDataPersonRepository(modelContext: modelContext)
        let contextRepository = SwiftDataContextRepository(modelContext: modelContext)
        let scheduler: NotificationScheduling = UserNotificationScheduler()
        let backupReminderScheduler = BackupReminderScheduler(notificationScheduler: scheduler)
        let service = ReminderService(
            repository: reminderRepository,
            notificationScheduler: scheduler,
            personRepository: personRepository,
            contextRepository: contextRepository
        )
        let people = PersonService(repository: personRepository)
        let contexts = ContextService(
            repository: contextRepository,
            personRepository: personRepository
        )
        let organizationDeletion = OrganizationDeletionService(
            personRepository: personRepository,
            contextRepository: contextRepository,
            reminderService: service,
            personCascade: SwiftDataPersonCascadeDeleter(modelContext: modelContext)
        )
        let exportService = BackupExportService(
            reminderRepository: reminderRepository,
            personRepository: personRepository,
            contextRepository: contextRepository
        )
        let storeReplacer = SwiftDataBackupStoreReplacer(modelContext: modelContext)
        let importService = BackupImportService(store: storeReplacer, reminderService: service)

        return .success(
            LifeCueAppComposition(
                container: container,
                reminderService: service,
                personService: people,
                contextService: contexts,
                organizationDeletionService: organizationDeletion,
                ocrService: VisionOCRService(),
                textExtractor: DeterministicReminderTextExtractor(),
                calendarService: EventKitCalendarService(),
                backupExportService: exportService,
                backupImportService: importService,
                backupReminderScheduler: backupReminderScheduler,
                notificationScheduler: scheduler,
                listViewModel: ReminderListViewModel(service: service)
            )
        )
    }
}
