import Foundation

/// Application service for reminder CRUD + local notification lifecycle.
@MainActor
final class ReminderService {
    private let repository: ReminderRepository
    private let personRepository: PersonRepository
    private let contextRepository: ContextRepository
    private let notificationScheduler: NotificationScheduling
    private let ruleEngine: ReminderRuleEngine
    private let calendar: Calendar
    private var clock: () -> Date
    private(set) var lastAuthorizationStatus: NotificationAuthorizationStatus = .notDetermined
    private(set) var lastFetchSkippedCorruptRecordCount: Int = 0

    /// Per-reminder token so a newer async schedule op supersedes an older one.
    private var scheduleGeneration: [UUID: UInt64] = [:]

    init(
        repository: ReminderRepository,
        notificationScheduler: NotificationScheduling,
        personRepository: PersonRepository? = nil,
        contextRepository: ContextRepository? = nil,
        ruleEngine: ReminderRuleEngine = ReminderRuleEngine(),
        calendar: Calendar = .current,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.repository = repository
        self.personRepository = personRepository ?? InMemoryPersonRepository()
        self.contextRepository = contextRepository ?? InMemoryContextRepository()
        self.notificationScheduler = notificationScheduler
        self.ruleEngine = ruleEngine
        self.calendar = calendar
        self.clock = clock
    }

    func allReminders() throws -> [Reminder] {
        try loadReminders().reminders
    }

    func loadReminders() throws -> ReminderFetchOutcome {
        let outcome = try repository.fetchAllOutcome()
        lastFetchSkippedCorruptRecordCount = outcome.skippedCorruptRecordIDs.count
        return outcome
    }

    func reminder(id: UUID) throws -> Reminder? {
        try repository.fetch(id: id)
    }

    @discardableResult
    func create(
        title: String,
        eventDate: Date,
        includeTime: Bool,
        eventTime: Date?,
        note: String? = nil,
        rules: [ReminderRule]? = nil,
        timeZoneIdentifier: String? = nil,
        personID: UUID? = nil,
        contextID: UUID? = nil
    ) async throws -> ReminderMutationResult {
        try ensureCanCreateActiveReminder()
        try validateMetadata(personID: personID, contextID: contextID, existing: nil)
        let includeExact = includeTime
        let resolvedRules = rules ?? ReminderRule.productDefaults(includeExactAtEvent: includeExact)
        let zone = timeZoneIdentifier ?? calendar.timeZone.identifier
        var zoneCalendar = calendar
        if let tz = TimeZone(identifier: zone) {
            zoneCalendar.timeZone = tz
        }
        let resolvedEventTime: DateComponents?
        if includeTime {
            resolvedEventTime = Reminder.timeComponents(
                from: eventTime ?? eventDate,
                calendar: zoneCalendar
            )
        } else {
            resolvedEventTime = LifeCueSettings.defaultTimeForNewDateOnlyReminder()
        }
        let reminder = try ReminderFactory.make(
            title: title,
            eventDate: Reminder.dateComponents(from: eventDate, calendar: zoneCalendar),
            eventTime: resolvedEventTime,
            timeZoneIdentifier: zone,
            note: note,
            personID: personID,
            contextID: contextID,
            rules: resolvedRules,
            snooze: nil,
            now: clock()
        )
        try ReminderRuleValidator.validate(
            rules: reminder.rules,
            calendar: reminder.calendarInStoredTimeZone(template: calendar)
        )
        try repository.save(reminder)
        let outcome = await syncNotifications(for: reminder, requestAuth: true)
        return ReminderMutationResult(reminder: reminder, scheduleOutcome: outcome)
    }

    /// Creates a Reminder from a user-confirmed extraction draft.
    /// Call only after explicit Create Reminder — never from OCR/extraction alone.
    @discardableResult
    func createFromConfirmedDraft(
        _ draft: ReminderDraft,
        rules: [ReminderRule]? = nil
    ) async throws -> ReminderMutationResult {
        try ensureCanCreateActiveReminder()
        try validateMetadata(personID: draft.personID, contextID: draft.contextID, existing: nil)
        let input = try ReminderDraftConverter.makeConfirmedInput(from: draft)
        let resolvedRules = rules ?? ReminderRule.productDefaults(
            includeExactAtEvent: input.includeExactAtEvent
        )
        let resolvedEventTime = input.eventTime ?? LifeCueSettings.defaultTimeForNewDateOnlyReminder()
        let reminder = try ReminderFactory.make(
            title: input.title,
            eventDate: input.eventDate,
            eventTime: resolvedEventTime,
            timeZoneIdentifier: input.timeZoneIdentifier,
            note: input.note,
            personID: draft.personID,
            contextID: draft.contextID,
            rules: resolvedRules,
            snooze: nil,
            now: clock()
        )
        try ReminderRuleValidator.validate(
            rules: reminder.rules,
            calendar: reminder.calendarInStoredTimeZone(template: calendar)
        )
        try repository.save(reminder)
        let outcome = await syncNotifications(for: reminder, requestAuth: true)
        return ReminderMutationResult(reminder: reminder, scheduleOutcome: outcome)
    }

    @discardableResult
    func update(_ reminder: Reminder) async throws -> ReminderMutationResult {
        guard let existing = try repository.fetch(id: reminder.id) else {
            throw ReminderRepositoryError.notFound
        }
        var updated = reminder
        updated.title = reminder.trimmedTitle
        guard !updated.title.isEmpty else { throw ReminderValidationError.emptyTitle }
        guard updated.eventDate.year != nil,
              updated.eventDate.month != nil,
              updated.eventDate.day != nil else {
            throw ReminderValidationError.missingEventDate
        }
        try validateMetadata(personID: updated.personID, contextID: updated.contextID, existing: existing)
        updated.note = Reminder.normalizedNote(reminder.note)
        updated.rules = updated.rules.filter { $0.ruleType != .snoozeOneOff }
        try ReminderRuleValidator.validate(
            rules: updated.rules,
            calendar: updated.calendarInStoredTimeZone(template: calendar)
        )
        updated.updatedAt = clock()

        // Person/Context are organizational metadata: do not clear snooze or reschedule.
        let personOrContextOnly =
            !hasStandingScheduleChange(from: existing, to: updated)
            && existing.title == updated.title
            && existing.note == updated.note
        if personOrContextOnly {
            updated.snooze = existing.snooze
            try repository.save(updated)
            return ReminderMutationResult(reminder: updated, scheduleOutcome: .nothingToSchedule)
        }

        // Schedule-relevant (or title/note) edit clears temporary snooze and rebuilds notifications.
        updated.snooze = nil
        try repository.save(updated)
        let outcome = await syncNotifications(for: updated, requestAuth: true)
        return ReminderMutationResult(reminder: updated, scheduleOutcome: outcome)
    }

    @discardableResult
    func complete(id: UUID) async throws -> ReminderMutationResult {
        guard var reminder = try repository.fetch(id: id) else {
            throw ReminderRepositoryError.notFound
        }
        // Invalidate any in-flight schedule before cancelling so a late add is compensated.
        invalidateScheduleGeneration(for: reminder.id)
        let now = clock()
        reminder.status = .completed
        reminder.completedAt = now
        reminder.updatedAt = now
        reminder.snooze = nil
        try repository.save(reminder)
        await cancelAllNotifications(forReminderID: reminder.id)
        return ReminderMutationResult(reminder: reminder, scheduleOutcome: .nothingToSchedule)
    }

    func delete(id: UUID) async throws {
        // Invalidate in-flight schedule first, then cancel existing pending notifications.
        invalidateScheduleGeneration(for: id)
        await cancelAllNotifications(forReminderID: id)
        try repository.delete(id: id)
    }

    @discardableResult
    func snooze(id: UUID, option: SnoozeOption) async throws -> ReminderMutationResult {
        guard var reminder = try repository.fetch(id: id) else {
            throw ReminderRepositoryError.notFound
        }
        guard reminder.status == .active else {
            return ReminderMutationResult(reminder: reminder, scheduleOutcome: .nothingToSchedule)
        }

        let fireAt = snoozeDate(for: option, from: clock())
        // Standing rules untouched — only temporary snooze state changes.
        reminder.snooze = ReminderSnoozeState(until: fireAt)
        reminder.updatedAt = clock()
        try repository.save(reminder)
        let outcome = await syncNotifications(for: reminder, requestAuth: true)
        return ReminderMutationResult(reminder: reminder, scheduleOutcome: outcome)
    }

    @discardableResult
    func reschedule(
        id: UUID,
        eventDate: Date,
        includeTime: Bool,
        eventTime: Date?
    ) async throws -> ReminderMutationResult {
        guard var reminder = try repository.fetch(id: id) else {
            throw ReminderRepositoryError.notFound
        }
        let zoneCalendar = reminder.calendarInStoredTimeZone(template: calendar)
        reminder.eventDate = Reminder.dateComponents(from: eventDate, calendar: zoneCalendar)
        reminder.eventTime = includeTime
            ? Reminder.timeComponents(from: eventTime ?? eventDate, calendar: zoneCalendar)
            : nil
        reminder.snooze = nil
        reminder.updatedAt = clock()
        try repository.save(reminder)
        let outcome = await syncNotifications(for: reminder, requestAuth: true)
        return ReminderMutationResult(reminder: reminder, scheduleOutcome: outcome)
    }

    func homeSections() throws -> [ReminderHomeSection: [Reminder]] {
        let classifier = ReminderHomeClassifier(calendar: calendar, now: clock())
        return classifier.grouped(try loadReminders().reminders)
    }

    /// Removes orphan LifeCue notifications and rebuilds schedules for active reminders.
    ///
    /// Also the V1 **replenishment** path for recurring reminders: each call regenerates
    /// the next bounded horizon from `now`, so consumed occurrences are replaced when
    /// LifeCue becomes active again (launch or foreground).
    ///
    /// When desired occurrences exceed `maxPendingNotifications`, nearest future fire
    /// times are scheduled first; farther ones remain eligible on later reconciles.
    @discardableResult
    func reconcileAllNotifications() async -> NotificationReconcileResult {
        lastAuthorizationStatus = await notificationScheduler.authorizationStatus()

        let pending = await notificationScheduler.pendingIdentifiers(
            prefix: NotificationIdentifier.reminderPrefix
        )
        let reminders: [Reminder]
        do {
            reminders = try loadReminders().reminders
        } catch {
            return .persistenceFailure
        }

        let activeIDs = Set(
            reminders
                .filter { $0.status == .active }
                .map(\.id)
        )

        // Cancel notifications for deleted / completed / unknown reminders.
        var orphanIDs = Set<String>()
        for identifier in pending {
            guard let reminderID = NotificationIdentifier.reminderID(from: identifier) else {
                if NotificationIdentifier.isLifeCueIdentifier(identifier) {
                    orphanIDs.insert(identifier)
                }
                continue
            }
            if !activeIDs.contains(reminderID) {
                orphanIDs.insert(identifier)
            }
        }
        if !orphanIDs.isEmpty {
            await notificationScheduler.cancel(identifiers: Array(orphanIDs))
        }

        guard canSchedule(lastAuthorizationStatus) else { return .permissionDenied }

        // Re-fetch active reminders and clear expired snooze stamps before allocating budget.
        var activeReminders: [Reminder] = []
        for reminderID in reminders.filter({ $0.status == .active }).map(\.id) {
            guard var latest = try? repository.fetch(id: reminderID),
                  latest.status == .active
            else {
                continue
            }
            if let snooze = latest.snooze, !snooze.isActive(relativeTo: clock()) {
                latest.snooze = nil
                latest.updatedAt = clock()
                try? repository.save(latest)
            }
            activeReminders.append(latest)
        }

        let allocation = allocateNotificationBudget(among: activeReminders, now: clock())

        // Clear existing active schedules before applying the budgeted nearest set so
        // mid-reconcile pending count never intentionally exceeds the safety budget.
        for reminder in activeReminders {
            await cancelAllNotifications(forReminderID: reminder.id)
        }

        var schedulingFailed = false
        for reminder in activeReminders {
            let allowed = allocation[reminder.id] ?? []
            let outcome = await syncNotifications(
                for: reminder,
                requestAuth: false,
                allowedOccurrences: allowed
            )
            if case .schedulingFailed = outcome {
                schedulingFailed = true
            }
        }

        return schedulingFailed ? .schedulingFailure : .success
    }

    // MARK: - Capacity

    private func ensureCanCreateActiveReminder() throws {
        let limit = ruleEngine.policy.maxActiveReminders
        let activeCount = try repository.fetchAll().filter { $0.status == .active }.count
        guard activeCount < limit else {
            throw ReminderValidationError.activeReminderLimitReached(limit: limit)
        }
    }

    private func validateMetadata(
        personID: UUID?,
        contextID: UUID?,
        existing: Reminder?
    ) throws {
        if let personID {
            guard let person = try personRepository.fetch(id: personID) else {
                throw ReminderValidationError.invalidPerson
            }
            // New selection must be active; already-linked archived person may remain on edit.
            if !person.isActive {
                guard existing?.personID == personID else {
                    throw ReminderValidationError.invalidPerson
                }
            }
        }
        if let contextID {
            guard let context = try contextRepository.fetch(id: contextID) else {
                throw ReminderValidationError.invalidContext
            }
            if !context.isActive {
                guard existing?.contextID == contextID else {
                    throw ReminderValidationError.invalidContext
                }
            }
            // Person-specific context must belong to the reminder's selected person.
            if let owner = context.personID {
                guard personID == owner else {
                    throw ReminderValidationError.invalidContext
                }
            }
        }
    }

    /// Schedule-relevant fields only. Person/Context are organizational metadata.
    private func hasStandingScheduleChange(from old: Reminder, to new: Reminder) -> Bool {
        old.eventDate != new.eventDate
            || old.eventTime != new.eventTime
            || old.timeZoneIdentifier != new.timeZoneIdentifier
            || old.rules != new.rules
            || old.status != new.status
    }

    /// Selects nearest future occurrences across reminders up to the pending-notification budget.
    private func allocateNotificationBudget(
        among reminders: [Reminder],
        now: Date
    ) -> [UUID: [ReminderOccurrence]] {
        struct Candidate {
            let reminderID: UUID
            let occurrence: ReminderOccurrence
        }

        var candidates: [Candidate] = []
        for reminder in reminders where reminder.status == .active {
            let occurrences = ruleEngine.occurrences(for: reminder, now: now, onlyFuture: true)
            for occurrence in occurrences {
                candidates.append(Candidate(reminderID: reminder.id, occurrence: occurrence))
            }
        }

        candidates.sort { lhs, rhs in
            if lhs.occurrence.fireAt != rhs.occurrence.fireAt {
                return lhs.occurrence.fireAt < rhs.occurrence.fireAt
            }
            // Stable tie-break: reminder id then occurrence key.
            if lhs.reminderID != rhs.reminderID {
                return lhs.reminderID.uuidString < rhs.reminderID.uuidString
            }
            return lhs.occurrence.occurrenceKey < rhs.occurrence.occurrenceKey
        }

        let budget = ruleEngine.policy.maxPendingNotifications
        let selected = candidates.prefix(budget)

        var allocation: [UUID: [ReminderOccurrence]] = [:]
        for candidate in selected {
            allocation[candidate.reminderID, default: []].append(candidate.occurrence)
        }
        return allocation
    }

    private func remainingNotificationSlots(excludingReminderID reminderID: UUID) async -> Int {
        let pending = await notificationScheduler.pendingIdentifiers(
            prefix: NotificationIdentifier.reminderPrefix
        )
        let others = pending.filter { identifier in
            NotificationIdentifier.reminderID(from: identifier) != reminderID
        }
        return max(0, ruleEngine.policy.maxPendingNotifications - others.count)
    }

    // MARK: - Notifications

    private func syncNotifications(
        for reminder: Reminder,
        requestAuth: Bool,
        allowedOccurrences: [ReminderOccurrence]? = nil
    ) async -> ReminderScheduleOutcome {
        let generation = nextGeneration(for: reminder.id)

        if requestAuth {
            lastAuthorizationStatus = await notificationScheduler.requestAuthorizationIfNeeded()
        } else {
            lastAuthorizationStatus = await notificationScheduler.authorizationStatus()
        }

        guard isCurrent(generation, for: reminder.id) else { return .superseded }

        // Rebuild this reminder's LifeCue notifications from the current desired set.
        await cancelAllNotifications(forReminderID: reminder.id)
        guard isCurrent(generation, for: reminder.id) else { return .superseded }

        // Authoritative reload: never schedule from a stale reconcile/mutation snapshot
        // after awaits (delete/complete/edit may have already won).
        guard var scheduleSource = try? repository.fetch(id: reminder.id) else {
            return .nothingToSchedule
        }
        guard scheduleSource.status == .active else {
            return .nothingToSchedule
        }
        guard isCurrent(generation, for: reminder.id) else { return .superseded }

        guard canSchedule(lastAuthorizationStatus) else { return .permissionDenied }

        if let snooze = scheduleSource.snooze, !snooze.isActive(relativeTo: clock()) {
            scheduleSource.snooze = nil
        }

        // Capture repository mutation stamp so a later edit/snooze cannot be overwritten
        // by this in-flight schedule even if generation checks alone were insufficient.
        let expectedUpdatedAt = scheduleSource.updatedAt

        // If a newer mutation already persisted different schedule-relevant state under a
        // newer generation, we are superseded. If generation still matches, trust repo.
        guard isCurrent(generation, for: reminder.id) else { return .superseded }
        guard isScheduleStillValid(
            reminderID: reminder.id,
            expectedGeneration: generation,
            expectedUpdatedAt: expectedUpdatedAt
        ) else {
            return .superseded
        }

        let occurrences: [ReminderOccurrence]
        if let allowedOccurrences {
            // Reconcile already chose nearest-across-reminders; schedule exactly that set
            // (may be empty when this reminder's fires are outside the current budget window).
            occurrences = allowedOccurrences.sorted { $0.fireAt < $1.fireAt }
        } else {
            var desired = ruleEngine.occurrences(
                for: scheduleSource,
                now: clock(),
                onlyFuture: true
            )
            let slots = await remainingNotificationSlots(excludingReminderID: scheduleSource.id)
            guard isCurrent(generation, for: reminder.id) else { return .superseded }
            if desired.count > slots {
                desired = Array(desired.prefix(slots))
            }
            occurrences = desired
        }

        guard !occurrences.isEmpty else { return .nothingToSchedule }

        let title = NotificationContentBuilder.title(for: scheduleSource)
        let body = NotificationContentBuilder.body(
            for: scheduleSource,
            calendar: scheduleSource.calendarInStoredTimeZone(template: calendar)
        )

        let requests: [ScheduledNotificationRequest] = occurrences.map { occurrence in
            let identifier = NotificationIdentifier.occurrence(
                reminderID: scheduleSource.id,
                generation: generation,
                ruleID: occurrence.ruleID,
                occurrenceKey: occurrence.occurrenceKey
            )
            return ScheduledNotificationRequest(
                identifier: identifier,
                fireAt: occurrence.fireAt,
                title: title,
                body: body,
                reminderID: scheduleSource.id,
                ruleID: occurrence.ruleID,
                occurrenceKey: occurrence.occurrenceKey,
                timeZoneIdentifier: scheduleSource.timeZoneIdentifier
            )
        }
        let intendedIdentifiers = requests.map(\.identifier)
        var attemptedIdentifiers: [String] = []
        var scheduledCount = 0
        var failure = false

        for request in requests {
            guard isCurrent(generation, for: reminder.id) else {
                await cancelIdentifiers(attemptedIdentifiers)
                return .superseded
            }
            // Re-check repository so a delete/complete/edit that raced cannot leave
            // notifications from this stale schedule operation.
            if !isScheduleStillValid(
                reminderID: reminder.id,
                expectedGeneration: generation,
                expectedUpdatedAt: expectedUpdatedAt
            ) {
                await cancelIdentifiers(attemptedIdentifiers)
                await cancelIdentifiers(intendedIdentifiers)
                return .superseded
            }

            // Soft capacity guard for single-reminder sync paths (create/update/snooze).
            if allowedOccurrences == nil {
                let slots = await remainingNotificationSlots(excludingReminderID: scheduleSource.id)
                if slots <= 0 {
                    break
                }
            }

            attemptedIdentifiers.append(request.identifier)

            do {
                try await notificationScheduler.schedule(request)
                scheduledCount += 1
            } catch {
                failure = true
            }

            guard isCurrent(generation, for: reminder.id) else {
                await cancelIdentifiers(attemptedIdentifiers)
                await cancelIdentifiers(intendedIdentifiers)
                return .superseded
            }
        }

        guard isCurrent(generation, for: reminder.id) else {
            await cancelIdentifiers(intendedIdentifiers)
            return .superseded
        }
        if !isScheduleStillValid(
            reminderID: reminder.id,
            expectedGeneration: generation,
            expectedUpdatedAt: expectedUpdatedAt
        ) {
            await cancelIdentifiers(intendedIdentifiers)
            return .superseded
        }
        if failure { return .schedulingFailed }
        if scheduledCount == 0 { return .nothingToSchedule }
        return .scheduled(scheduledCount)
    }

    /// True when generation is current and repository still holds the same active reminder stamp.
    private func isScheduleStillValid(
        reminderID: UUID,
        expectedGeneration: UInt64,
        expectedUpdatedAt: Date
    ) -> Bool {
        guard isCurrent(expectedGeneration, for: reminderID) else { return false }
        guard let latest = try? repository.fetch(id: reminderID) else { return false }
        guard latest.status == .active else { return false }
        return latest.updatedAt == expectedUpdatedAt
    }

    private func cancelAllNotifications(forReminderID reminderID: UUID) async {
        let prefix = NotificationIdentifier.prefix(for: reminderID)
        let pending = await notificationScheduler.pendingIdentifiers(prefix: prefix)
        await notificationScheduler.cancel(identifiers: pending)
    }

    private func cancelIdentifiers(_ identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        await notificationScheduler.cancel(identifiers: Array(Set(identifiers)))
    }

    /// Bumps generation so any in-flight schedule for this reminder becomes superseded.
    @discardableResult
    private func invalidateScheduleGeneration(for reminderID: UUID) -> UInt64 {
        nextGeneration(for: reminderID)
    }

    private func nextGeneration(for reminderID: UUID) -> UInt64 {
        let next = (scheduleGeneration[reminderID] ?? 0) &+ 1
        scheduleGeneration[reminderID] = next
        return next
    }

    private func isCurrent(_ generation: UInt64, for reminderID: UUID) -> Bool {
        scheduleGeneration[reminderID] == generation
    }

    private func canSchedule(_ status: NotificationAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied, .unsupported:
            return false
        }
    }

    private func snoozeDate(for option: SnoozeOption, from now: Date) -> Date {
        switch option {
        case .laterToday:
            return calendar.date(byAdding: .hour, value: 3, to: now)
                ?? now.addingTimeInterval(3 * 60 * 60)
        case .tomorrow:
            let start = calendar.startOfDay(for: now)
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: start),
               let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) {
                return fire
            }
            return now.addingTimeInterval(24 * 60 * 60)
        case .nextWeek:
            return calendar.date(byAdding: .day, value: 7, to: now)
                ?? now.addingTimeInterval(7 * 24 * 60 * 60)
        case .custom(let date):
            return date
        }
    }
}

enum SnoozeOption: Equatable, Sendable {
    case laterToday
    case tomorrow
    case nextWeek
    case custom(Date)
}
