import Foundation
import Observation

@MainActor
@Observable
final class ReminderListViewModel {
    private let service: ReminderService

    var overdue: [Reminder] = []
    var today: [Reminder] = []
    var upcoming: [Reminder] = []
    var completed: [Reminder] = []
    var errorMessage: String?
    var corruptRecordsWarning: String?
    var isLoading = false

    /// Ephemeral search/filter state (not persisted).
    var filterState = ReminderHomeFilterState()

    var isEmpty: Bool {
        overdue.isEmpty && today.isEmpty && upcoming.isEmpty && completed.isEmpty
    }

    /// True when there are reminders, but the current search/filter yields none.
    var isFilterEmpty: Bool {
        !isEmpty && displayedOverdue.isEmpty && displayedToday.isEmpty
            && displayedUpcoming.isEmpty && displayedCompleted.isEmpty
    }

    init(service: ReminderService) {
        self.service = service
    }

    // MARK: - Displayed sections (presentation only)

    var displayedOverdue: [Reminder] {
        guard filterState.status == .all else { return [] }
        return applyFilters(to: overdue, forcedSection: .overdue)
    }

    var displayedToday: [Reminder] {
        switch filterState.status {
        case .all, .today:
            return applyFilters(to: today, forcedSection: .today)
        case .upcoming, .completed:
            return []
        }
    }

    var displayedUpcoming: [Reminder] {
        switch filterState.status {
        case .all, .upcoming:
            return applyFilters(to: upcoming, forcedSection: .upcoming)
        case .today, .completed:
            return []
        }
    }

    var displayedCompleted: [Reminder] {
        guard filterState.status == .completed else { return [] }
        return applyFilters(to: completed, forcedSection: nil)
    }

    func load() {
        isLoading = true
        defer { isLoading = false }
        do {
            let sections = try service.homeSections()
            overdue = sections[.overdue] ?? []
            today = sections[.today] ?? []
            upcoming = sections[.upcoming] ?? []
            completed = try service.allReminders()
                .filter { $0.status == .completed }
                .sorted { lhs, rhs in
                    let left = lhs.completedAt ?? lhs.updatedAt
                    let right = rhs.completedAt ?? rhs.updatedAt
                    return left > right
                }
            errorMessage = nil
            if service.lastFetchSkippedCorruptRecordCount > 0 {
                corruptRecordsWarning = "One or more reminders couldn't be loaded. Your other reminders are still available."
            } else {
                corruptRecordsWarning = nil
            }
        } catch {
            errorMessage = "Couldn't load reminders."
            corruptRecordsWarning = nil
        }
    }

    func complete(_ reminder: Reminder) async {
        do {
            try await service.complete(id: reminder.id)
            load()
        } catch {
            errorMessage = "Couldn't complete reminder."
        }
    }

    func delete(_ reminder: Reminder) async {
        do {
            try await service.delete(id: reminder.id)
            load()
        } catch {
            errorMessage = "Couldn't delete reminder."
        }
    }

    func clearFiltersPreservingSearch() {
        filterState.clearFiltersPreservingSearch()
    }

    func clearAllSearchAndFilters() {
        filterState.clearAll()
    }

    // MARK: - Private

    private func applyFilters(to reminders: [Reminder], forcedSection: ReminderHomeSection?) -> [Reminder] {
        // Person/Context name resolution is injected by HomeView via `configureResolvers`
        // when available; until then match without names (IDs still work).
        let personNames = personNameResolver
        let contextNames = contextNameResolver
        return ReminderHomeFiltering.filter(
            reminders: reminders,
            state: filterState,
            personName: { personNames?($0) },
            contextName: { contextNames?($0) },
            homeSection: { _ in forcedSection }
        )
    }

    /// Optional resolvers set by HomeView so search can match Person/Context names.
    var personNameResolver: ((Reminder) -> String?)?
    var contextNameResolver: ((Reminder) -> String?)?
}
