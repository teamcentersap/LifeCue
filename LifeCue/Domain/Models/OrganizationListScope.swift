import Foundation

/// People / Contexts list scope. Active | Archived only — no "All".
enum OrganizationListScope: String, CaseIterable, Identifiable, Equatable, Sendable {
    case active
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "Active"
        case .archived: return "Archived"
        }
    }

    /// Default when opening People or Contexts.
    static var `default`: OrganizationListScope { .active }

    /// Contract: only Active and Archived exist (no All).
    static var segmentTitles: [String] { allCases.map(\.title) }
}

enum OrganizationListPresentation {
    static func emptyPeopleMessage(for scope: OrganizationListScope) -> String {
        switch scope {
        case .active:
            return "No active people yet."
        case .archived:
            return "No archived people."
        }
    }

    static func emptyContextsMessage(for scope: OrganizationListScope) -> String {
        switch scope {
        case .active:
            return "No active contexts yet."
        case .archived:
            return "No archived contexts."
        }
    }

    static func people(from all: [Person], scope: OrganizationListScope) -> [Person] {
        switch scope {
        case .active:
            return all.filter(\.isActive)
        case .archived:
            return all.filter(\.isArchived)
        }
    }

    static func contexts(from all: [ReminderContext], scope: OrganizationListScope) -> [ReminderContext] {
        switch scope {
        case .active:
            return all.filter(\.isActive)
        case .archived:
            return all.filter(\.isArchived)
        }
    }
}
