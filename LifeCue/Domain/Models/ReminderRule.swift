import Foundation

enum ReminderOffsetUnit: String, Codable, CaseIterable, Sendable {
    case minute
    case hour
    case day
    case week
    case month
}

/// Standing schedule rule types. Snooze is separate temporary state — not a ReminderRule.
enum ReminderRuleType: String, Codable, Sendable {
    case exactAtEvent
    case beforeEvent
    /// Legacy encoded value from Sprint 2; migrated into `ReminderSnoozeState` on load.
    case snoozeOneOff
    case recurring
    /// Reserved; windows attach to recurring rules via `dateWindow` in Sprint 6.
    case dateWindow
}

/// Temporary snooze scheduling state. Standing `Reminder.rules` remain the source of truth.
struct ReminderSnoozeState: Equatable, Sendable, Codable {
    var until: Date

    func isActive(relativeTo now: Date) -> Bool {
        until > now
    }
}

/// A single standing scheduling rule attached to a reminder.
struct ReminderRule: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    var ruleType: ReminderRuleType
    var offsetValue: Int?
    var offsetUnit: ReminderOffsetUnit?
    var enabled: Bool
    /// Present when `ruleType == .recurring`.
    var recurrence: ReminderRecurrence?
    /// Optional inclusive date window restricting recurrence anchors.
    var dateWindow: ReminderDateWindow?

    init(
        id: UUID = UUID(),
        ruleType: ReminderRuleType,
        offsetValue: Int? = nil,
        offsetUnit: ReminderOffsetUnit? = nil,
        enabled: Bool = true,
        recurrence: ReminderRecurrence? = nil,
        dateWindow: ReminderDateWindow? = nil
    ) {
        self.id = id
        self.ruleType = ruleType
        self.offsetValue = offsetValue
        self.offsetUnit = offsetUnit
        self.enabled = enabled
        self.recurrence = recurrence
        self.dateWindow = dateWindow
    }

    static func exactAtEvent(enabled: Bool = true) -> ReminderRule {
        ReminderRule(ruleType: .exactAtEvent, enabled: enabled)
    }

    static func beforeEvent(
        value: Int,
        unit: ReminderOffsetUnit,
        enabled: Bool = true
    ) -> ReminderRule {
        ReminderRule(
            ruleType: .beforeEvent,
            offsetValue: value,
            offsetUnit: unit,
            enabled: enabled
        )
    }

    static func recurring(
        _ recurrence: ReminderRecurrence,
        window: ReminderDateWindow? = nil,
        enabled: Bool = true
    ) -> ReminderRule {
        ReminderRule(
            ruleType: .recurring,
            enabled: enabled,
            recurrence: recurrence,
            dateWindow: window
        )
    }

    /// Product-default standing schedule: 1 week before · 1 day before.
    static func productDefaults(includeExactAtEvent: Bool) -> [ReminderRule] {
        var rules: [ReminderRule] = [
            .beforeEvent(value: 1, unit: .week),
            .beforeEvent(value: 1, unit: .day)
        ]
        if includeExactAtEvent {
            rules.insert(.exactAtEvent(), at: 0)
        }
        return rules
    }
}

/// A calculated fire instant produced by the rule engine.
struct ReminderOccurrence: Equatable, Sendable {
    let ruleID: UUID
    /// Deterministic key for this fire instant (stable across rebuilds).
    let occurrenceKey: String
    let fireAt: Date
    let ruleType: ReminderRuleType
    let isSnooze: Bool

    /// Stable identity: ruleID + occurrenceKey (combined with reminderID at notification layer).
    var identity: String {
        "\(ruleID.uuidString).\(occurrenceKey)"
    }

    static func occurrenceKey(for fireAt: Date) -> String {
        let seconds = Int(fireAt.timeIntervalSince1970)
        return "t\(seconds)"
    }
}
