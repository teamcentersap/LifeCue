import Foundation

struct ExtractedTimeToken: Equatable, Sendable {
    let components: DateComponents
    let range: NSRange
    let rawSnippet: String
}

enum ExtractionTimeParser {
    static func findTimes(in text: String) -> [ExtractedTimeToken] {
        var tokens: [ExtractedTimeToken] = []
        tokens.append(contentsOf: findTwelveHourWithMinutes(in: text))
        tokens.append(contentsOf: findTwelveHourBare(in: text))
        tokens.append(contentsOf: findTwentyFourHour(in: text))
        return deduplicateOverlapping(tokens)
    }

    private static func findTwelveHourWithMinutes(in text: String) -> [ExtractedTimeToken] {
        // 4:00 PM, 4.30 pm, 04:00 a.m.
        let pattern = #"\b([1-9]|1[0-2])(?:[:.]([0-5]\d))\s*([AaPp])\.?[Mm]\.?\b"#
        return matchTimes(in: text, pattern: pattern) { ns, match in
            guard let hour12 = Int(ns.substring(with: match.range(at: 1))),
                  let minute = Int(ns.substring(with: match.range(at: 2)))
            else { return nil }
            let meridiem = ns.substring(with: match.range(at: 3)).uppercased()
            let hour = convert12to24(hour12: hour12, isPM: meridiem == "P")
            return DateComponents(hour: hour, minute: minute)
        }
    }

    private static func findTwelveHourBare(in text: String) -> [ExtractedTimeToken] {
        // 4 PM, 4pm — avoid matching inside longer digit runs.
        let pattern = #"\b([1-9]|1[0-2])\s*([AaPp])\.?[Mm]\.?\b"#
        return matchTimes(in: text, pattern: pattern) { ns, match in
            guard let hour12 = Int(ns.substring(with: match.range(at: 1))) else { return nil }
            let meridiem = ns.substring(with: match.range(at: 2)).uppercased()
            let hour = convert12to24(hour12: hour12, isPM: meridiem == "P")
            return DateComponents(hour: hour, minute: 0)
        }
    }

    private static func findTwentyFourHour(in text: String) -> [ExtractedTimeToken] {
        // 16:00, 09:30 — skip if preceded by date-like slash/dash digits already consumed elsewhere.
        let pattern = #"\b([01]?\d|2[0-3]):([0-5]\d)\b"#
        return matchTimes(in: text, pattern: pattern) { ns, match in
            // Reject if this looks like part of a phone/price by checking surrounding digits.
            let full = match.range
            if full.location > 0 {
                let prev = ns.substring(with: NSRange(location: full.location - 1, length: 1))
                if prev.rangeOfCharacter(from: .decimalDigits) != nil { return nil }
                if prev == "$" || prev == "£" || prev == "€" { return nil }
            }
            let end = full.location + full.length
            if end < ns.length {
                let next = ns.substring(with: NSRange(location: end, length: 1))
                if next.rangeOfCharacter(from: .decimalDigits) != nil { return nil }
            }
            // Skip if AM/PM follows (handled by 12-hour parsers).
            let after = min(ns.length, end + 6)
            if after > end {
                let trailing = ns.substring(with: NSRange(location: end, length: after - end)).lowercased()
                if trailing.range(of: #"^\s*[ap]\.?m"#, options: .regularExpression) != nil {
                    return nil
                }
            }
            guard let hour = Int(ns.substring(with: match.range(at: 1))),
                  let minute = Int(ns.substring(with: match.range(at: 2)))
            else { return nil }
            return DateComponents(hour: hour, minute: minute)
        }
    }

    private static func convert12to24(hour12: Int, isPM: Bool) -> Int {
        switch (hour12, isPM) {
        case (12, false): return 0
        case (12, true): return 12
        case (_, true): return hour12 + 12
        default: return hour12
        }
    }

    private static func matchTimes(
        in text: String,
        pattern: String,
        map: (NSString, NSTextCheckingResult) -> DateComponents?
    ) -> [ExtractedTimeToken] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard let comps = map(ns, match) else { return nil }
            return ExtractedTimeToken(
                components: comps,
                range: match.range,
                rawSnippet: ns.substring(with: match.range)
            )
        }
    }

    private static func deduplicateOverlapping(_ tokens: [ExtractedTimeToken]) -> [ExtractedTimeToken] {
        let sorted = tokens.sorted { lhs, rhs in
            if lhs.range.location != rhs.range.location {
                return lhs.range.location < rhs.range.location
            }
            return lhs.range.length > rhs.range.length
        }
        var kept: [ExtractedTimeToken] = []
        for token in sorted {
            if kept.contains(where: { NSIntersectionRange($0.range, token.range).length > 0 }) {
                continue
            }
            kept.append(token)
        }
        return kept
    }
}
