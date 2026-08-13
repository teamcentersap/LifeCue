import Foundation

struct ExtractedDateToken: Equatable, Sendable {
    let components: DateComponents
    /// Inclusive UTF-16 NSRange in the normalized full text.
    let range: NSRange
    let rawSnippet: String
    /// Named / ISO / relative are unambiguous; numeric may need confirmation.
    let isStructurallyAmbiguous: Bool
    /// Alternate interpretation when numeric MDY/DMY both valid.
    let alternateComponents: DateComponents?
}

enum ExtractionDateParser {
    private static let monthMap: [String: Int] = [
        "january": 1, "jan": 1,
        "february": 2, "feb": 2,
        "march": 3, "mar": 3,
        "april": 4, "apr": 4,
        "may": 5,
        "june": 6, "jun": 6,
        "july": 7, "jul": 7,
        "august": 8, "aug": 8,
        "september": 9, "sept": 9, "sep": 9,
        "october": 10, "oct": 10,
        "november": 11, "nov": 11,
        "december": 12, "dec": 12
    ]

    private static let monthAlternation = monthMap.keys.sorted { $0.count > $1.count }.joined(separator: "|")

    static func findDates(in text: String, configuration: ExtractionConfiguration) -> [ExtractedDateToken] {
        var tokens: [ExtractedDateToken] = []
        tokens.append(contentsOf: findRelative(in: text, configuration: configuration))
        tokens.append(contentsOf: findISO(in: text, configuration: configuration))
        tokens.append(contentsOf: findDayMonthYear(in: text, configuration: configuration))
        tokens.append(contentsOf: findMonthDayYear(in: text, configuration: configuration))
        tokens.append(contentsOf: findNumeric(in: text, configuration: configuration))
        return deduplicateOverlapping(tokens)
    }

    private static func findRelative(
        in text: String,
        configuration: ExtractionConfiguration
    ) -> [ExtractedDateToken] {
        let pattern = #"\b(today|tomorrow|yesterday)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        let calendar = configuration.calendar
        let refDay = calendar.startOfDay(for: configuration.referenceDate)

        return matches.compactMap { match -> ExtractedDateToken? in
            let raw = ns.substring(with: match.range).lowercased()
            let offset: Int
            switch raw {
            case "today": offset = 0
            case "tomorrow": offset = 1
            case "yesterday": offset = -1
            default: return nil
            }
            guard let date = calendar.date(byAdding: .day, value: offset, to: refDay) else {
                return nil
            }
            let comps = calendar.dateComponents([.year, .month, .day], from: date)
            return ExtractedDateToken(
                components: comps,
                range: match.range,
                rawSnippet: ns.substring(with: match.range),
                isStructurallyAmbiguous: false,
                alternateComponents: nil
            )
        }
    }

    private static func findISO(
        in text: String,
        configuration: ExtractionConfiguration
    ) -> [ExtractedDateToken] {
        let pattern = #"\b(\d{4})-(\d{2})-(\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges == 4,
                  let y = Int(ns.substring(with: match.range(at: 1))),
                  let m = Int(ns.substring(with: match.range(at: 2))),
                  let d = Int(ns.substring(with: match.range(at: 3))),
                  isValidDate(year: y, month: m, day: d, calendar: configuration.calendar)
            else { return nil }
            return ExtractedDateToken(
                components: DateComponents(year: y, month: m, day: d),
                range: match.range,
                rawSnippet: ns.substring(with: match.range),
                isStructurallyAmbiguous: false,
                alternateComponents: nil
            )
        }
    }

    private static func findDayMonthYear(
        in text: String,
        configuration: ExtractionConfiguration
    ) -> [ExtractedDateToken] {
        let pattern = #"\b(\d{1,2})(?:st|nd|rd|th)?\s+("# + monthAlternation + #")(?:\s*,?\s*(\d{4}))?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let ns = text as NSString
        let refYear = configuration.calendar.component(.year, from: configuration.referenceDate)
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges >= 3,
                  let day = Int(ns.substring(with: match.range(at: 1)))
            else { return nil }
            let monthName = ns.substring(with: match.range(at: 2)).lowercased()
            guard let month = monthMap[monthName] else { return nil }
            let year: Int
            if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound {
                year = Int(ns.substring(with: match.range(at: 3))) ?? refYear
            } else {
                year = refYear
            }
            guard isValidDate(year: year, month: month, day: day, calendar: configuration.calendar) else {
                return nil
            }
            return ExtractedDateToken(
                components: DateComponents(year: year, month: month, day: day),
                range: match.range,
                rawSnippet: ns.substring(with: match.range),
                isStructurallyAmbiguous: false,
                alternateComponents: nil
            )
        }
    }

    private static func findMonthDayYear(
        in text: String,
        configuration: ExtractionConfiguration
    ) -> [ExtractedDateToken] {
        let pattern = #"\b("# + monthAlternation + #")\s+(\d{1,2})(?:st|nd|rd|th)?(?:\s*,?\s*(\d{4}))?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let ns = text as NSString
        let refYear = configuration.calendar.component(.year, from: configuration.referenceDate)
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let monthName = ns.substring(with: match.range(at: 1)).lowercased()
            guard let month = monthMap[monthName],
                  let day = Int(ns.substring(with: match.range(at: 2)))
            else { return nil }
            let year: Int
            if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound {
                year = Int(ns.substring(with: match.range(at: 3))) ?? refYear
            } else {
                year = refYear
            }
            guard isValidDate(year: year, month: month, day: day, calendar: configuration.calendar) else {
                return nil
            }
            return ExtractedDateToken(
                components: DateComponents(year: year, month: month, day: day),
                range: match.range,
                rawSnippet: ns.substring(with: match.range),
                isStructurallyAmbiguous: false,
                alternateComponents: nil
            )
        }
    }

    private static func findNumeric(
        in text: String,
        configuration: ExtractionConfiguration
    ) -> [ExtractedDateToken] {
        let pattern = #"\b(\d{1,2})([./-])(\d{1,2})\2(\d{2,4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let calendar = configuration.calendar
        let prefersMonthFirst = configuration.prefersMonthFirstNumericDates

        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard let a = Int(ns.substring(with: match.range(at: 1))),
                  let b = Int(ns.substring(with: match.range(at: 3))),
                  var year = Int(ns.substring(with: match.range(at: 4)))
            else { return nil }

            if year < 100 {
                // Conservative century window anchored to reference year (no invention beyond pivot).
                let refYear = calendar.component(.year, from: configuration.referenceDate)
                let century = (refYear / 100) * 100
                year += century
                if year > refYear + 30 {
                    year -= 100
                }
            }

            let dayFirst = DateComponents(year: year, month: b, day: a)
            let monthFirst = DateComponents(year: year, month: a, day: b)
            let dayFirstValid = isValidDate(year: year, month: b, day: a, calendar: calendar)
            let monthFirstValid = isValidDate(year: year, month: a, day: b, calendar: calendar)

            // Unambiguous when only one ordering is a valid calendar date.
            if dayFirstValid && !monthFirstValid {
                return ExtractedDateToken(
                    components: dayFirst,
                    range: match.range,
                    rawSnippet: ns.substring(with: match.range),
                    isStructurallyAmbiguous: false,
                    alternateComponents: nil
                )
            }
            if monthFirstValid && !dayFirstValid {
                return ExtractedDateToken(
                    components: monthFirst,
                    range: match.range,
                    rawSnippet: ns.substring(with: match.range),
                    isStructurallyAmbiguous: false,
                    alternateComponents: nil
                )
            }
            guard dayFirstValid && monthFirstValid else { return nil }

            // Both valid (e.g. 05/06/2026): structurally ambiguous — do not silently commit.
            let preferred = prefersMonthFirst ? monthFirst : dayFirst
            let alternate = prefersMonthFirst ? dayFirst : monthFirst
            if preferred == alternate {
                return ExtractedDateToken(
                    components: preferred,
                    range: match.range,
                    rawSnippet: ns.substring(with: match.range),
                    isStructurallyAmbiguous: false,
                    alternateComponents: nil
                )
            }
            return ExtractedDateToken(
                components: preferred,
                range: match.range,
                rawSnippet: ns.substring(with: match.range),
                isStructurallyAmbiguous: true,
                alternateComponents: alternate
            )
        }
    }

    private static func isValidDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Bool {
        var comps = DateComponents(year: year, month: month, day: day)
        comps.hour = 12
        guard let date = calendar.date(from: comps) else { return false }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == year && back.month == month && back.day == day
    }

    private static func deduplicateOverlapping(_ tokens: [ExtractedDateToken]) -> [ExtractedDateToken] {
        let sorted = tokens.sorted { lhs, rhs in
            if lhs.range.location != rhs.range.location {
                return lhs.range.location < rhs.range.location
            }
            return lhs.range.length > rhs.range.length
        }
        var kept: [ExtractedDateToken] = []
        for token in sorted {
            if kept.contains(where: { NSIntersectionRange($0.range, token.range).length > 0 }) {
                continue
            }
            kept.append(token)
        }
        return kept
    }
}
