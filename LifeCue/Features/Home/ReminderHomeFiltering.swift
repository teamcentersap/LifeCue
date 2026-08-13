import Foundation

/// Home status scope for Sprint 11 filtering (presentation only).
enum ReminderHomeStatusFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case all
    case today
    case upcoming
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .completed: return "Completed"
        }
    }
}

/// Ephemeral Home search/filter state — not persisted.
struct ReminderHomeFilterState: Equatable, Sendable {
    var searchText: String = ""
    var personID: UUID?
    var contextID: UUID?
    var status: ReminderHomeStatusFilter = .all

    var normalizedQuery: String {
        ReminderHomeFiltering.normalizedQuery(searchText)
    }

    /// Count of active non-default filter dimensions (excludes empty search).
    var activeFilterCount: Int {
        var count = 0
        if personID != nil { count += 1 }
        if contextID != nil { count += 1 }
        if status != .all { count += 1 }
        return count
    }

    var hasActiveSearch: Bool {
        !normalizedQuery.isEmpty
    }

    var hasActiveFilters: Bool {
        activeFilterCount > 0
    }

    var isNarrowing: Bool {
        hasActiveSearch || hasActiveFilters
    }

    mutating func clearFiltersPreservingSearch() {
        personID = nil
        contextID = nil
        status = .all
    }

    mutating func clearAll() {
        searchText = ""
        clearFiltersPreservingSearch()
    }
}

/// Pure in-memory Home search + AND filtering. Does not mutate reminders or schedules.
enum ReminderHomeFiltering {
    static func normalizedQuery(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Case-insensitive match against title, note, person name, and context name.
    static func matchesSearch(
        reminder: Reminder,
        query: String,
        personName: String?,
        contextName: String?
    ) -> Bool {
        let q = normalizedQuery(query)
        guard !q.isEmpty else { return true }

        if reminder.title.lowercased().contains(q) { return true }
        if let note = reminder.note, note.lowercased().contains(q) { return true }
        if let personName, searchablePersonTokens(personName).contains(where: { $0.contains(q) }) {
            return true
        }
        if let contextName, searchableContextTokens(contextName).contains(where: { $0.contains(q) }) {
            return true
        }
        return false
    }

    static func matchesPerson(_ reminder: Reminder, personID: UUID?) -> Bool {
        guard let personID else { return true }
        return reminder.personID == personID
    }

    static func matchesContext(_ reminder: Reminder, contextID: UUID?) -> Bool {
        guard let contextID else { return true }
        return reminder.contextID == contextID
    }

    static func matchesStatus(
        _ reminder: Reminder,
        status: ReminderHomeStatusFilter,
        homeSection: ReminderHomeSection?
    ) -> Bool {
        switch status {
        case .all:
            return reminder.status == .active
        case .today:
            return reminder.status == .active && homeSection == .today
        case .upcoming:
            return reminder.status == .active && homeSection == .upcoming
        case .completed:
            return reminder.status == .completed
        }
    }

    static func matches(
        reminder: Reminder,
        state: ReminderHomeFilterState,
        personName: String?,
        contextName: String?,
        homeSection: ReminderHomeSection?
    ) -> Bool {
        matchesStatus(reminder, status: state.status, homeSection: homeSection)
            && matchesPerson(reminder, personID: state.personID)
            && matchesContext(reminder, contextID: state.contextID)
            && matchesSearch(
                reminder: reminder,
                query: state.searchText,
                personName: personName,
                contextName: contextName
            )
    }

    static func filter(
        reminders: [Reminder],
        state: ReminderHomeFilterState,
        personName: (Reminder) -> String?,
        contextName: (Reminder) -> String?,
        homeSection: (Reminder) -> ReminderHomeSection?
    ) -> [Reminder] {
        reminders.filter { reminder in
            matches(
                reminder: reminder,
                state: state,
                personName: personName(reminder),
                contextName: contextName(reminder),
                homeSection: homeSection(reminder)
            )
        }
    }

    /// Strip display-only "(archived)" so search still matches the underlying name.
    static func searchablePersonTokens(_ displayName: String) -> [String] {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutArchived = trimmed
            .replacingOccurrences(of: " (archived)", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return [trimmed.lowercased(), withoutArchived.lowercased()]
    }

    static func searchableContextTokens(_ displayName: String) -> [String] {
        searchablePersonTokens(displayName)
    }
}
