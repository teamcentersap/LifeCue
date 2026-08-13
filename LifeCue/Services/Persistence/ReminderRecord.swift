import Foundation
import SwiftData

@Model
final class ReminderRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var eventYear: Int
    var eventMonth: Int
    var eventDay: Int
    var eventHour: Int?
    var eventMinute: Int?
    var timeZoneIdentifier: String
    var note: String?
    /// Optional Person id. Nil on legacy records.
    var personID: UUID?
    /// Optional Context id. Nil on legacy records.
    var contextID: UUID?
    var statusRaw: String
    /// Versioned rules (+ optional snooze) JSON.
    var rulesJSON: Data = ReminderRuleCoding.emptyPayloadData
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    init(from reminder: Reminder) throws {
        self.id = reminder.id
        self.title = reminder.title
        self.eventYear = reminder.eventDate.year ?? 0
        self.eventMonth = reminder.eventDate.month ?? 0
        self.eventDay = reminder.eventDate.day ?? 0
        self.eventHour = reminder.eventTime?.hour
        self.eventMinute = reminder.eventTime?.minute
        self.timeZoneIdentifier = reminder.timeZoneIdentifier
        self.note = reminder.note
        self.personID = reminder.personID
        self.contextID = reminder.contextID
        self.statusRaw = reminder.status.rawValue
        self.rulesJSON = try ReminderRuleCoding.encode(rules: reminder.rules, snooze: reminder.snooze)
        self.createdAt = reminder.createdAt
        self.updatedAt = reminder.updatedAt
        self.completedAt = reminder.completedAt
    }

    func apply(_ reminder: Reminder) throws {
        title = reminder.title
        eventYear = reminder.eventDate.year ?? 0
        eventMonth = reminder.eventDate.month ?? 0
        eventDay = reminder.eventDate.day ?? 0
        eventHour = reminder.eventTime?.hour
        eventMinute = reminder.eventTime?.minute
        timeZoneIdentifier = reminder.timeZoneIdentifier
        note = reminder.note
        personID = reminder.personID
        contextID = reminder.contextID
        statusRaw = reminder.status.rawValue
        rulesJSON = try ReminderRuleCoding.encode(rules: reminder.rules, snooze: reminder.snooze)
        createdAt = reminder.createdAt
        updatedAt = reminder.updatedAt
        completedAt = reminder.completedAt
    }

    func asDomain() throws -> Reminder {
        guard TimeZone(identifier: timeZoneIdentifier) != nil else {
            throw ReminderRecordConversionError.invalidTimeZone
        }
        guard eventYear > 0, eventMonth > 0, eventDay > 0 else {
            throw ReminderRecordConversionError.invalidEventDate
        }

        let eventDate = DateComponents(year: eventYear, month: eventMonth, day: eventDay)
        let eventTime: DateComponents?
        if let eventHour, let eventMinute {
            eventTime = DateComponents(hour: eventHour, minute: eventMinute)
        } else {
            eventTime = nil
        }

        let payload = try ReminderRuleCoding.decode(rulesJSON)

        guard let status = ReminderStatus(rawValue: statusRaw) else {
            throw ReminderRecordConversionError.invalidStatus
        }

        return Reminder(
            id: id,
            title: title,
            eventDate: eventDate,
            eventTime: eventTime,
            timeZoneIdentifier: timeZoneIdentifier,
            note: note,
            personID: personID,
            contextID: contextID,
            status: status,
            rules: payload.rules,
            snooze: payload.snooze,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt
        )
    }
}
