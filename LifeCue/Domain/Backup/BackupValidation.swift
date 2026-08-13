import Foundation

enum BackupValidationError: Error, Equatable, Sendable {
    case unreadable
    case invalidJSON
    case wrongFormat
    case unsupportedSchema
    case missingRequiredField
    case duplicatePersonID
    case duplicateContextID
    case duplicateReminderID
    case duplicateRuleID
    case invalidDate
    case invalidTimeZone
    case invalidStatus
    case invalidRule
    case invalidPersonReference
    case invalidContextReference
    case personContextMismatch
    case emptyTitle
    case invalidEventDate
    case replaceFailed
    case fileTooLarge
}

enum BackupUserFacingError: Equatable, Sendable {
    case unsupportedSchema
    case invalidOrIncomplete
    case unreadable
    case invalidRelationships
    case restoreFailed
    case exportFailed
    case fileTooLarge

    var message: String {
        switch self {
        case .unsupportedSchema:
            return "This backup was created by a newer version of LifeCue. Please update LifeCue before importing it."
        case .invalidOrIncomplete:
            return "This LifeCue backup is invalid or incomplete."
        case .unreadable:
            return "LifeCue couldn't read this backup."
        case .invalidRelationships:
            return "This backup contains invalid People or Context relationships."
        case .restoreFailed:
            return "LifeCue couldn't restore this backup. Your current data was not changed."
        case .exportFailed:
            return "LifeCue couldn't create this backup."
        case .fileTooLarge:
            return "This backup file is too large to import."
        }
    }

    static func from(_ error: Error) -> BackupUserFacingError {
        if let validation = error as? BackupValidationError {
            switch validation {
            case .unsupportedSchema:
                return .unsupportedSchema
            case .unreadable, .invalidJSON:
                return .unreadable
            case .invalidPersonReference, .invalidContextReference, .personContextMismatch:
                return .invalidRelationships
            case .replaceFailed:
                return .restoreFailed
            case .fileTooLarge:
                return .fileTooLarge
            default:
                return .invalidOrIncomplete
            }
        }
        return .unreadable
    }
}

enum BackupMigrator {
    /// Migrates a decoded backup to the current schema shape. V1 is identity.
    static func migrateToCurrent(_ backup: LifeCueBackup) throws -> LifeCueBackup {
        if backup.schemaVersion > LifeCueBackup.maxSupportedSchemaVersion
            || backup.minimumReaderVersion > LifeCueBackup.maxSupportedSchemaVersion {
            throw BackupValidationError.unsupportedSchema
        }
        if backup.schemaVersion < 1 {
            throw BackupValidationError.unsupportedSchema
        }
        // Future: convert schemaVersion N → current here.
        return backup
    }
}

enum BackupValidator {
    /// Maximum `.lifecuebackup` import size (10 MB). Local-first reminder data should stay well below this.
    static let maxImportFileSizeBytes = 10 * 1024 * 1024

    static func validateImportFileSize(_ byteCount: Int) throws {
        guard byteCount <= maxImportFileSizeBytes else {
            throw BackupValidationError.fileTooLarge
        }
    }

    /// Validates a backup produced for export before writing to disk.
    static func validateExport(_ backup: LifeCueBackup) throws {
        try validateEnvelope(backup)
        let migrated = try BackupMigrator.migrateToCurrent(backup)
        try validateContents(migrated)
        let snapshot = try LifeCueBackupMapper.makeSnapshot(from: migrated)
        try validateDomainSnapshot(snapshot)
    }

    static func decodeAndValidate(data: Data) throws -> (LifeCueBackup, BackupDomainSnapshot) {
        try validateImportFileSize(data.count)
        let backup: LifeCueBackup
        do {
            let decoder = JSONDecoder()
            backup = try decoder.decode(LifeCueBackup.self, from: data)
        } catch let error as DecodingError {
            if case .keyNotFound = error {
                throw BackupValidationError.missingRequiredField
            }
            throw BackupValidationError.invalidJSON
        } catch {
            throw BackupValidationError.invalidJSON
        }

        try validateEnvelope(backup)
        let migrated = try BackupMigrator.migrateToCurrent(backup)
        try validateContents(migrated)
        let snapshot = try LifeCueBackupMapper.makeSnapshot(from: migrated)
        try validateDomainSnapshot(snapshot)
        return (migrated, snapshot)
    }

    static func validateEnvelope(_ backup: LifeCueBackup) throws {
        guard backup.format == LifeCueBackup.formatIdentifier else {
            throw BackupValidationError.wrongFormat
        }
        guard backup.schemaVersion >= 1 else {
            throw BackupValidationError.unsupportedSchema
        }
        guard backup.schemaVersion <= LifeCueBackup.maxSupportedSchemaVersion,
              backup.minimumReaderVersion <= LifeCueBackup.maxSupportedSchemaVersion
        else {
            throw BackupValidationError.unsupportedSchema
        }
        guard BackupJSONDate.decode(backup.exportedAt) != nil else {
            throw BackupValidationError.invalidDate
        }
    }

    static func validateContents(_ backup: LifeCueBackup) throws {
        try assertUniqueIDs(backup.people.map(\.id), error: .duplicatePersonID)
        try assertUniqueIDs(backup.contexts.map(\.id), error: .duplicateContextID)
        try assertUniqueIDs(backup.reminders.map(\.id), error: .duplicateReminderID)

        let personIDs = Set(backup.people.map(\.id))
        let contextByID = Dictionary(uniqueKeysWithValues: backup.contexts.map { ($0.id, $0) })

        for person in backup.people {
            if person.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw BackupValidationError.missingRequiredField
            }
            guard BackupJSONDate.decode(person.createdAt) != nil,
                  BackupJSONDate.decode(person.updatedAt) != nil
            else {
                throw BackupValidationError.invalidDate
            }
        }

        for context in backup.contexts {
            if context.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw BackupValidationError.missingRequiredField
            }
            guard BackupJSONDate.decode(context.createdAt) != nil,
                  BackupJSONDate.decode(context.updatedAt) != nil
            else {
                throw BackupValidationError.invalidDate
            }
            if let personID = context.personID, !personIDs.contains(personID) {
                throw BackupValidationError.invalidPersonReference
            }
        }

        var ruleIDs = Set<UUID>()
        for reminder in backup.reminders {
            if reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw BackupValidationError.emptyTitle
            }
            guard ReminderStatus(rawValue: reminder.status) != nil else {
                throw BackupValidationError.invalidStatus
            }
            guard TimeZone(identifier: reminder.timeZoneIdentifier) != nil else {
                throw BackupValidationError.invalidTimeZone
            }
            try validateDateComponents(reminder.eventDate)
            if let time = reminder.eventTime {
                guard (0...23).contains(time.hour), (0...59).contains(time.minute) else {
                    throw BackupValidationError.invalidEventDate
                }
            }
            guard BackupJSONDate.decode(reminder.createdAt) != nil,
                  BackupJSONDate.decode(reminder.updatedAt) != nil
            else {
                throw BackupValidationError.invalidDate
            }
            if let completedAt = reminder.completedAt, BackupJSONDate.decode(completedAt) == nil {
                throw BackupValidationError.invalidDate
            }
            if let snooze = reminder.snooze, BackupJSONDate.decode(snooze.until) == nil {
                throw BackupValidationError.invalidDate
            }

            if let personID = reminder.personID, !personIDs.contains(personID) {
                throw BackupValidationError.invalidPersonReference
            }
            if let contextID = reminder.contextID {
                guard let context = contextByID[contextID] else {
                    throw BackupValidationError.invalidContextReference
                }
                // Sprint 7: person-specific context must match reminder person.
                if let contextPersonID = context.personID {
                    guard let reminderPersonID = reminder.personID,
                          reminderPersonID == contextPersonID
                    else {
                        throw BackupValidationError.personContextMismatch
                    }
                }
            }

            for rule in reminder.rules {
                if !ruleIDs.insert(rule.id).inserted {
                    throw BackupValidationError.duplicateRuleID
                }
                guard ReminderRuleType(rawValue: rule.ruleType) != nil else {
                    throw BackupValidationError.invalidRule
                }
                if let unit = rule.offsetUnit, ReminderOffsetUnit(rawValue: unit) == nil {
                    throw BackupValidationError.invalidRule
                }
                if let recurrence = rule.recurrence {
                    guard ReminderRecurrenceFrequency(rawValue: recurrence.frequency) != nil,
                          recurrence.interval >= 1
                    else {
                        throw BackupValidationError.invalidRule
                    }
                }
                if let window = rule.dateWindow {
                    try validateDateComponents(window.startDate)
                    try validateDateComponents(window.endDate)
                }
            }
        }
    }

    static func validateDomainSnapshot(_ snapshot: BackupDomainSnapshot) throws {
        for reminder in snapshot.reminders {
            try ReminderRuleValidator.validate(rules: reminder.rules)
            if reminder.trimmedTitle.isEmpty {
                throw BackupValidationError.emptyTitle
            }
            guard reminder.eventDate.year != nil,
                  reminder.eventDate.month != nil,
                  reminder.eventDate.day != nil
            else {
                throw BackupValidationError.invalidEventDate
            }
        }
    }

    private static func validateDateComponents(_ components: LifeCueBackupDateComponents) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var comps = DateComponents(year: components.year, month: components.month, day: components.day)
        comps.hour = 12
        guard let date = calendar.date(from: comps) else {
            throw BackupValidationError.invalidEventDate
        }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == components.year,
              back.month == components.month,
              back.day == components.day
        else {
            throw BackupValidationError.invalidEventDate
        }
    }

    private static func assertUniqueIDs(_ ids: [UUID], error: BackupValidationError) throws {
        var seen = Set<UUID>()
        for id in ids {
            if !seen.insert(id).inserted {
                throw error
            }
        }
    }
}
