import Foundation

enum LifeCueProFeature: String, CaseIterable, Sendable {
    case imageCapture
    case recurrence
    case forward
    case backup
}

enum FeatureAccessPolicy {
    static let freeCapabilities = [
        "Manual reminders",
        "Notes",
        "One-time notifications",
        "Snooze, complete, and edit",
        "Optional People and Contexts",
        "Home and Calendar"
    ]

    static let proCapabilities = [
        "Upload Image and Take Photo",
        "On-device image extraction",
        "Repeating, yearly, and date-window reminders",
        "Forward",
        "Backup and Restore"
    ]

    static func isLocked(_ feature: LifeCueProFeature, isPro: Bool) -> Bool {
        isPro ? false : true
    }

    static func allows(_ feature: LifeCueProFeature, isPro: Bool) -> Bool {
        !isLocked(feature, isPro: isPro)
    }
}
