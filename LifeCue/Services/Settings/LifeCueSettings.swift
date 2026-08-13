import Foundation
import SwiftUI

enum LifeCueAppearance: String, CaseIterable, Codable, Sendable, Equatable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// App-level user preferences persisted in UserDefaults.
enum LifeCueSettings {
    static let defaultReminderTimeKey = "lifecue.settings.defaultReminderTime"
    static let appearanceKey = "lifecue.settings.appearance"

    static let fallbackDefaultHour = 9
    static let fallbackDefaultMinute = 0

    static var defaultReminderTime: DateComponents {
        get {
            guard let stored = UserDefaults.standard.dictionary(forKey: defaultReminderTimeKey) else {
                return fallbackDefaultReminderTime
            }
            return validatedTimeComponents(from: stored) ?? fallbackDefaultReminderTime
        }
        set {
            let hour = newValue.hour ?? fallbackDefaultHour
            let minute = newValue.minute ?? fallbackDefaultMinute
            UserDefaults.standard.set(
                ["hour": hour, "minute": minute],
                forKey: defaultReminderTimeKey
            )
        }
    }

    static var appearance: LifeCueAppearance {
        get {
            guard let raw = UserDefaults.standard.string(forKey: appearanceKey),
                  let value = LifeCueAppearance(rawValue: raw) else {
                return .system
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: appearanceKey)
        }
    }

    static var fallbackDefaultReminderTime: DateComponents {
        DateComponents(hour: fallbackDefaultHour, minute: fallbackDefaultMinute)
    }

    static func validatedTimeComponents(from stored: [String: Any]) -> DateComponents? {
        guard let hour = stored["hour"] as? Int,
              let minute = stored["minute"] as? Int,
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        return DateComponents(hour: hour, minute: minute)
    }

    /// Notification time for a newly created date-only reminder (persisted on the reminder).
    static func defaultTimeForNewDateOnlyReminder() -> DateComponents {
        defaultReminderTime
    }

    static var dateOnlyReminderFootnote: String {
        let timeText = formattedDefaultReminderTime()
        return "Date-only events use \(timeText) unless you set a time."
    }

    static func formattedDefaultReminderTime(calendar: Calendar = .current) -> String {
        let components = defaultReminderTime
        var dateComponents = DateComponents()
        dateComponents.hour = components.hour ?? fallbackDefaultHour
        dateComponents.minute = components.minute ?? fallbackDefaultMinute
        guard let date = calendar.date(from: dateComponents) else {
            return "9:00 AM"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

enum LifeCueBundleInfo {
    static var marketingVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    static var buildNumber: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "—"
    }
}

enum NotificationAuthorizationDisplay {
    static func label(for status: NotificationAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return "Allowed"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not Determined"
        case .unsupported:
            return "Restricted"
        }
    }

    static func showsOpenSettings(for status: NotificationAuthorizationStatus) -> Bool {
        switch status {
        case .denied, .unsupported:
            return true
        case .authorized, .provisional, .ephemeral, .notDetermined:
            return false
        }
    }
}
