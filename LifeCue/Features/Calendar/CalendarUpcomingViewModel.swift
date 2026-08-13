import Foundation

@MainActor
final class CalendarUpcomingViewModel: ObservableObject {
    @Published var authorizationStatus: CalendarAuthorizationStatus = .notDetermined
    @Published var calendars: [CalendarSource] = []
    @Published var selectedCalendarIDs: [String]? = nil
    @Published var events: [CalendarEvent] = []

    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service: CalendarServing

    init(service: CalendarServing) {
        self.service = service
    }

    func loadInitial() async {
        isLoading = true
        defer { isLoading = false }
        authorizationStatus = await service.authorizationStatus()

        switch authorizationStatus {
        case .fullAccess:
            await loadCalendarsAndEvents()
        case .notDetermined, .denied, .restricted, .unavailable:
            // UI handles explanation; no automatic requests.
            return
        }
    }

    func requestAccess() async {
        isLoading = true
        defer { isLoading = false }
        authorizationStatus = await service.requestFullAccessToEvents()
        if authorizationStatus == .fullAccess {
            await loadCalendarsAndEvents()
        }
    }

    private func loadCalendarsAndEvents() async {
        do {
            calendars = try await service.fetchAvailableCalendars()
            // For first sprint, keep it simple: if user hasn’t chosen, show all.
            selectedCalendarIDs = nil

            let now = Date()
            let start = Calendar.current.startOfDay(for: now)
            let end = Calendar.current.date(byAdding: .day, value: 30, to: start) ?? now.addingTimeInterval(30 * 86400)
            events = try await service.fetchEvents(from: start, to: end, calendarIdentifiers: selectedCalendarIDs)
        } catch {
            errorMessage = "Couldn't load calendar events."
        }
    }
}

