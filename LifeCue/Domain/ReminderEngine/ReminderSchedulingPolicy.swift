import Foundation

/// Explicit V1 scheduling / capacity policy decisions for LifeCue.
struct ReminderSchedulingPolicy: Equatable, Sendable {
    /// Date-only reminders (no `eventTime`) use **09:00** in the reminder timezone
    /// unless the user sets an explicit time.
    var defaultTimeOfDay: DateComponents

    /// Cap per-reminder desired local notifications before the global budget is applied.
    /// Apple keeps a system-limited pending set historically documented around **64**
    /// soonest local notifications per app; LifeCue stays well under that budget.
    var maxOccurrencesPerReminder: Int

    /// Do not generate recurrence anchors beyond this many days ahead of `now`.
    var horizonDays: Int

    /// Product limit: maximum **active** reminders (completed/deleted do not count).
    /// Separate from `maxPendingNotifications`.
    var maxActiveReminders: Int

    /// Internal safety budget for pending LifeCue notification requests app-wide.
    /// Conservative under Apple's historically documented ~64 pending local notifications.
    /// Not a user-facing reminder count.
    var maxPendingNotifications: Int

    static let `default` = ReminderSchedulingPolicy(
        defaultTimeOfDay: DateComponents(hour: 9, minute: 0),
        maxOccurrencesPerReminder: 16,
        /// ~2+ years so yearly reminders can schedule the next occurrence ahead.
        /// Daily still capped by `maxOccurrencesPerReminder` (Apple ~64 pending/app).
        horizonDays: 800,
        maxActiveReminders: 60,
        maxPendingNotifications: 56
    )
}
