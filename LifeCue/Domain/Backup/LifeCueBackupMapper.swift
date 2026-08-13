import Foundation

enum BackupJSONDate {
    private static let utc: TimeZone = TimeZone(secondsFromGMT: 0)!

    private static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = utc
        return formatter
    }()

    private static let withoutFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = utc
        return formatter
    }()

    static func encode(_ date: Date) -> String {
        withFractional.string(from: date)
    }

    static func decode(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return withFractional.date(from: trimmed) ?? withoutFractional.date(from: trimmed)
    }
}

enum LifeCueBackupMapper {
    static func makeBackup(
        people: [Person],
        contexts: [ReminderContext],
        reminders: [Reminder],
        exportedAt: Date
    ) -> LifeCueBackup {
        LifeCueBackup(
            format: LifeCueBackup.formatIdentifier,
            schemaVersion: LifeCueBackup.currentSchemaVersion,
            minimumReaderVersion: LifeCueBackup.currentMinimumReaderVersion,
            exportedAt: BackupJSONDate.encode(exportedAt),
            people: people.map(map(person:)),
            contexts: contexts.map(map(context:)),
            reminders: reminders.map(map(reminder:))
        )
    }

    static func makeSnapshot(from backup: LifeCueBackup) throws -> BackupDomainSnapshot {
        BackupDomainSnapshot(
            people: try backup.people.map(mapToDomain(person:)),
            contexts: try backup.contexts.map(mapToDomain(context:)),
            reminders: try backup.reminders.map(mapToDomain(reminder:))
        )
    }

    // MARK: - Domain → DTO

    private static func map(person: Person) -> LifeCueBackupPerson {
        LifeCueBackupPerson(
            id: person.id,
            name: person.name,
            relationship: person.relationship,
            iconName: person.iconName,
            colorToken: person.colorToken,
            isArchived: person.isArchived,
            createdAt: BackupJSONDate.encode(person.createdAt),
            updatedAt: BackupJSONDate.encode(person.updatedAt)
        )
    }

    private static func map(context: ReminderContext) -> LifeCueBackupContext {
        LifeCueBackupContext(
            id: context.id,
            name: context.name,
            iconName: context.iconName,
            colorToken: context.colorToken,
            personID: context.personID,
            isArchived: context.isArchived,
            createdAt: BackupJSONDate.encode(context.createdAt),
            updatedAt: BackupJSONDate.encode(context.updatedAt)
        )
    }

    private static func map(reminder: Reminder) -> LifeCueBackupReminder {
        LifeCueBackupReminder(
            id: reminder.id,
            title: reminder.title,
            eventDate: LifeCueBackupDateComponents(
                year: reminder.eventDate.year ?? 0,
                month: reminder.eventDate.month ?? 0,
                day: reminder.eventDate.day ?? 0
            ),
            eventTime: reminder.eventTime.map {
                LifeCueBackupTimeComponents(hour: $0.hour ?? 0, minute: $0.minute ?? 0)
            },
            timeZoneIdentifier: reminder.timeZoneIdentifier,
            note: reminder.note,
            personID: reminder.personID,
            contextID: reminder.contextID,
            status: reminder.status.rawValue,
            rules: reminder.rules.map(map(rule:)),
            snooze: reminder.snooze.map { LifeCueBackupSnooze(until: BackupJSONDate.encode($0.until)) },
            createdAt: BackupJSONDate.encode(reminder.createdAt),
            updatedAt: BackupJSONDate.encode(reminder.updatedAt),
            completedAt: reminder.completedAt.map(BackupJSONDate.encode)
        )
    }

    private static func map(rule: ReminderRule) -> LifeCueBackupRule {
        LifeCueBackupRule(
            id: rule.id,
            ruleType: rule.ruleType.rawValue,
            offsetValue: rule.offsetValue,
            offsetUnit: rule.offsetUnit?.rawValue,
            enabled: rule.enabled,
            recurrence: rule.recurrence.map(map(recurrence:)),
            dateWindow: rule.dateWindow.map(map(window:))
        )
    }

    private static func map(recurrence: ReminderRecurrence) -> LifeCueBackupRecurrence {
        LifeCueBackupRecurrence(
            frequency: recurrence.frequency.rawValue,
            interval: recurrence.interval,
            weekdays: recurrence.weekdays,
            dayOfMonth: recurrence.dayOfMonth
        )
    }

    private static func map(window: ReminderDateWindow) -> LifeCueBackupDateWindow {
        LifeCueBackupDateWindow(
            startDate: LifeCueBackupDateComponents(
                year: window.startDate.year ?? 0,
                month: window.startDate.month ?? 0,
                day: window.startDate.day ?? 0
            ),
            endDate: LifeCueBackupDateComponents(
                year: window.endDate.year ?? 0,
                month: window.endDate.month ?? 0,
                day: window.endDate.day ?? 0
            )
        )
    }

    // MARK: - DTO → Domain

    private static func mapToDomain(person: LifeCueBackupPerson) throws -> Person {
        guard let createdAt = BackupJSONDate.decode(person.createdAt),
              let updatedAt = BackupJSONDate.decode(person.updatedAt)
        else {
            throw BackupValidationError.invalidDate
        }
        return Person(
            id: person.id,
            name: person.name,
            relationship: person.relationship,
            iconName: person.iconName,
            colorToken: person.colorToken,
            isArchived: person.isArchived,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func mapToDomain(context: LifeCueBackupContext) throws -> ReminderContext {
        guard let createdAt = BackupJSONDate.decode(context.createdAt),
              let updatedAt = BackupJSONDate.decode(context.updatedAt)
        else {
            throw BackupValidationError.invalidDate
        }
        return ReminderContext(
            id: context.id,
            name: context.name,
            iconName: context.iconName,
            colorToken: context.colorToken,
            personID: context.personID,
            isArchived: context.isArchived,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func mapToDomain(reminder: LifeCueBackupReminder) throws -> Reminder {
        guard let createdAt = BackupJSONDate.decode(reminder.createdAt),
              let updatedAt = BackupJSONDate.decode(reminder.updatedAt)
        else {
            throw BackupValidationError.invalidDate
        }
        let completedAt: Date?
        if let raw = reminder.completedAt {
            guard let decoded = BackupJSONDate.decode(raw) else {
                throw BackupValidationError.invalidDate
            }
            completedAt = decoded
        } else {
            completedAt = nil
        }

        let snooze: ReminderSnoozeState?
        if let raw = reminder.snooze {
            guard let until = BackupJSONDate.decode(raw.until) else {
                throw BackupValidationError.invalidDate
            }
            snooze = ReminderSnoozeState(until: until)
        } else {
            snooze = nil
        }

        guard let status = ReminderStatus(rawValue: reminder.status) else {
            throw BackupValidationError.invalidStatus
        }

        let eventTime: DateComponents?
        if let time = reminder.eventTime {
            eventTime = DateComponents(hour: time.hour, minute: time.minute)
        } else {
            eventTime = nil
        }

        return Reminder(
            id: reminder.id,
            title: reminder.title,
            eventDate: DateComponents(
                year: reminder.eventDate.year,
                month: reminder.eventDate.month,
                day: reminder.eventDate.day
            ),
            eventTime: eventTime,
            timeZoneIdentifier: reminder.timeZoneIdentifier,
            note: reminder.note,
            personID: reminder.personID,
            contextID: reminder.contextID,
            status: status,
            rules: try reminder.rules.map(mapToDomain(rule:)),
            snooze: snooze,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt
        )
    }

    private static func mapToDomain(rule: LifeCueBackupRule) throws -> ReminderRule {
        guard let ruleType = ReminderRuleType(rawValue: rule.ruleType) else {
            throw BackupValidationError.invalidRule
        }
        let offsetUnit: ReminderOffsetUnit?
        if let raw = rule.offsetUnit {
            guard let unit = ReminderOffsetUnit(rawValue: raw) else {
                throw BackupValidationError.invalidRule
            }
            offsetUnit = unit
        } else {
            offsetUnit = nil
        }
        return ReminderRule(
            id: rule.id,
            ruleType: ruleType,
            offsetValue: rule.offsetValue,
            offsetUnit: offsetUnit,
            enabled: rule.enabled,
            recurrence: try rule.recurrence.map(mapToDomain(recurrence:)),
            dateWindow: try rule.dateWindow.map(mapToDomain(window:))
        )
    }

    private static func mapToDomain(recurrence: LifeCueBackupRecurrence) throws -> ReminderRecurrence {
        guard let frequency = ReminderRecurrenceFrequency(rawValue: recurrence.frequency) else {
            throw BackupValidationError.invalidRule
        }
        return ReminderRecurrence(
            frequency: frequency,
            interval: recurrence.interval,
            weekdays: recurrence.weekdays,
            dayOfMonth: recurrence.dayOfMonth
        )
    }

    private static func mapToDomain(window: LifeCueBackupDateWindow) throws -> ReminderDateWindow {
        ReminderDateWindow(
            startDate: DateComponents(
                year: window.startDate.year,
                month: window.startDate.month,
                day: window.startDate.day
            ),
            endDate: DateComponents(
                year: window.endDate.year,
                month: window.endDate.month,
                day: window.endDate.day
            )
        )
    }
}
