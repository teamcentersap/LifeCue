import Foundation

/// Field-level extraction outcome for Sprint 5 review.
enum ExtractionFieldState<Value: Equatable & Sendable>: Equatable, Sendable {
    case missing
    case resolved(Value)
    /// Multiple plausible values; do not invent a single answer.
    case ambiguous(candidates: [Value], rawSnippet: String?)

    var resolvedValue: Value? {
        if case .resolved(let value) = self { return value }
        return nil
    }

    var isMissing: Bool {
        if case .missing = self { return true }
        return false
    }

    var isAmbiguous: Bool {
        if case .ambiguous = self { return true }
        return false
    }

    var needsConfirmation: Bool {
        switch self {
        case .missing, .ambiguous:
            return true
        case .resolved:
            return false
        }
    }
}
