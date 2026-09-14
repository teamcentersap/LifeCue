import Foundation

enum AppConfig {
    static let displayName = "LifeCue"
    static let bundleID = "com.lifecue.app"
    static let proProductID = "com.lifecue.app.pro.lifetime"
    /// Lifetime Pro IAP is required for photo capture, repeating reminders, Forward, and Backup.
    static let monetizationEnabled = true
}
