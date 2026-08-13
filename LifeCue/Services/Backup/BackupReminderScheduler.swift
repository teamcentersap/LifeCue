import Foundation

/// Schedules the optional app-level Backup Reminder notification.
///
/// Uses `NotificationScheduling.scheduleAppNotification` — never touches ReminderService,
/// ReminderRuleEngine, or reminder reconciliation.
@MainActor
final class BackupReminderScheduler {
    static let enabledKey = "lifecue.backupReminder.enabled"
    static let intervalKey = "lifecue.backupReminder.interval"
    static let enabledAtKey = "lifecue.backupReminder.enabledAt"

    private let notificationScheduler: NotificationScheduling
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let clock: () -> Date

    init(
        notificationScheduler: NotificationScheduling,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        clock: @escaping () -> Date = Date.init
    ) {
        self.notificationScheduler = notificationScheduler
        self.defaults = defaults
        self.calendar = calendar
        self.clock = clock
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    var interval: BackupReminderInterval {
        get {
            let raw = defaults.string(forKey: Self.intervalKey) ?? BackupReminderInterval.oneWeek.rawValue
            return BackupReminderInterval(rawValue: raw) ?? .oneWeek
        }
        set { defaults.set(newValue.rawValue, forKey: Self.intervalKey) }
    }

    var enabledAt: Date? {
        get { defaults.object(forKey: Self.enabledAtKey) as? Date }
        set { defaults.set(newValue, forKey: Self.enabledAtKey) }
    }

    /// Enables backup reminder, requests notification permission, and schedules the first reminder.
    /// First reminder fires at enable date + interval at 9:00 AM local — never immediately.
    func enable() async -> NotificationAuthorizationStatus {
        isEnabled = true
        enabledAt = clock()
        let status = await notificationScheduler.requestAuthorizationIfNeeded()
        if canSchedule(status) {
            await rescheduleFromEnable()
        }
        return status
    }

    func disable() async {
        isEnabled = false
        enabledAt = nil
        await cancelOnly()
    }

    func setInterval(_ newInterval: BackupReminderInterval) async {
        guard interval != newInterval else { return }
        interval = newInterval
        guard isEnabled else { return }
        await rescheduleFromEnable()
    }

    /// Called after a successful backup export. Reschedules from export date + interval.
    func rescheduleAfterSuccessfulExport(at exportDate: Date) async {
        guard isEnabled else { return }
        await cancelOnly()
        await schedule(from: exportDate)
    }

    func cancelOnly() async {
        await notificationScheduler.cancel(identifiers: [BackupReminderNotification.identifier])
    }

    /// Next fire date: base start-of-day + interval at 9:00 AM in device-local calendar.
    static func nextFireDate(
        from base: Date,
        interval: BackupReminderInterval,
        calendar: Calendar
    ) -> Date {
        let dayStart = calendar.startOfDay(for: base)
        let afterInterval = interval.adding(to: dayStart, calendar: calendar)
        var components = calendar.dateComponents([.year, .month, .day], from: afterInterval)
        components.hour = BackupReminderNotification.fireTimeHour
        components.minute = BackupReminderNotification.fireTimeMinute
        components.second = 0
        return calendar.date(from: components) ?? afterInterval
    }

    // MARK: - Private

    private func rescheduleFromEnable() async {
        await cancelOnly()
        let base = enabledAt ?? clock()
        await schedule(from: base)
    }

    private func schedule(from baseDate: Date) async {
        let status = await notificationScheduler.authorizationStatus()
        guard canSchedule(status) else { return }

        var fireAt = Self.nextFireDate(from: baseDate, interval: interval, calendar: calendar)
        let now = clock()
        while fireAt <= now {
            fireAt = Self.nextFireDate(from: fireAt, interval: interval, calendar: calendar)
        }

        let request = ScheduledAppNotificationRequest(
            identifier: BackupReminderNotification.identifier,
            fireAt: fireAt,
            title: BackupReminderNotification.title,
            body: BackupReminderNotification.body,
            userInfo: [
                BackupReminderNotification.userInfoTypeKey: BackupReminderNotification.userInfoTypeValue
            ]
        )
        try? await notificationScheduler.scheduleAppNotification(request)
    }

    private func canSchedule(_ status: NotificationAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied, .unsupported:
            return false
        }
    }
}
