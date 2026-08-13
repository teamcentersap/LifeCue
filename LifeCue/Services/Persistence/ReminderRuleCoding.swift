import Foundation

enum ReminderRuleCodingError: Error, Equatable, LocalizedError {
    case malformed
    case missingVersion
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .malformed:
            return "Reminder schedule data is corrupted."
        case .missingVersion:
            return "Reminder schedule data is missing a schema version."
        case .unsupportedVersion(let version):
            return "Unsupported reminder schedule schema version \(version)."
        }
    }
}

/// Versioned persistence envelope for standing reminder rules (+ optional snooze).
struct ReminderRulesPayload: Codable, Equatable, Sendable {
    /// Sprint 6: recurrence + dateWindow fields on ReminderRule.
    static let currentSchemaVersion = 2
    /// Sprint 2.1 / Sprint 5 payload version (still accepted).
    static let legacySchemaVersion = 1

    var schemaVersion: Int
    var rules: [ReminderRule]
    var snooze: ReminderSnoozeState?

    init(rules: [ReminderRule], snooze: ReminderSnoozeState? = nil) {
        self.schemaVersion = Self.currentSchemaVersion
        self.rules = rules.filter { $0.ruleType != .snoozeOneOff }
        self.snooze = snooze
    }
}

enum ReminderRuleCoding {
    static let emptyPayloadData: Data = {
        Data(#"{"schemaVersion":2,"rules":[]}"#.utf8)
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func encode(rules: [ReminderRule], snooze: ReminderSnoozeState?) throws -> Data {
        try encoder.encode(ReminderRulesPayload(rules: rules, snooze: snooze))
    }

    /// Decodes versioned payload.
    /// - Schema v1 and v2 accepted; v1 rules gain nil recurrence/window.
    /// - Sprint 2 bare `[ReminderRule]` arrays accepted as implicit v1.
    /// - Malformed / unsupported data throws (never silently becomes []).
    static func decode(_ data: Data) throws -> ReminderRulesPayload {
        guard !data.isEmpty else { throw ReminderRuleCodingError.malformed }

        if let payload = try? decoder.decode(ReminderRulesPayload.self, from: data) {
            guard payload.schemaVersion > 0 else {
                throw ReminderRuleCodingError.missingVersion
            }
            guard payload.schemaVersion == ReminderRulesPayload.currentSchemaVersion
                || payload.schemaVersion == ReminderRulesPayload.legacySchemaVersion
            else {
                throw ReminderRuleCodingError.unsupportedVersion(payload.schemaVersion)
            }
            // Normalize to current envelope; Codable already maps missing v2 fields to nil.
            return ReminderRulesPayload(
                rules: payload.rules.filter { $0.ruleType != .snoozeOneOff },
                snooze: payload.snooze
            )
        }

        // Backward compatibility: Sprint 2 stored a bare rules array (implicit v1).
        if let legacyRules = try? decoder.decode([ReminderRule].self, from: data) {
            return ReminderRulesPayload(
                rules: legacyRules.filter { $0.ruleType != .snoozeOneOff },
                snooze: nil
            )
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let version = object["schemaVersion"] as? Int,
               version != ReminderRulesPayload.currentSchemaVersion,
               version != ReminderRulesPayload.legacySchemaVersion {
                throw ReminderRuleCodingError.unsupportedVersion(version)
            }
            if object["rules"] != nil, object["schemaVersion"] == nil {
                throw ReminderRuleCodingError.missingVersion
            }
        }

        throw ReminderRuleCodingError.malformed
    }
}
