import Foundation

/// Internal-only authorization status for Calendar integration.
enum CalendarAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case fullAccess
    case denied
    case restricted
    case unavailable
}

/// Lightweight Calendar source model for filtering events.
struct CalendarSource: Identifiable, Equatable, Sendable {
    let id: String // EKCalendar.calendarIdentifier
    let title: String
}

/// Abstraction over EventKit so SwiftUI views never talk to EKEventStore directly.
protocol CalendarServing: AnyObject {
    func authorizationStatus() async -> CalendarAuthorizationStatus
    func requestFullAccessToEvents() async -> CalendarAuthorizationStatus

    /// Returns events in the provided absolute date range (from..to).
    /// `calendarIdentifiers == nil` means "all accessible calendars".
    func fetchEvents(
        from: Date,
        to: Date,
        calendarIdentifiers: [String]?
    ) async throws -> [CalendarEvent]

    /// Returns a simple list of accessible calendars.
    func fetchAvailableCalendars() async throws -> [CalendarSource]
}

