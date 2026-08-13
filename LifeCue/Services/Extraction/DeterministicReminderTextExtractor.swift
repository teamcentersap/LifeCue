import Foundation

/// Local deterministic OCR → ReminderDraft. Never creates a Reminder.
final class DeterministicReminderTextExtractor: ReminderTextExtracting, @unchecked Sendable {
    func extract(from result: OCRResult, configuration: ExtractionConfiguration) -> ReminderDraft {
        let raw = result.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, result.status == .success || result.hasRecognizedText else {
            return .empty(sourceText: result.fullText, configuration: configuration)
        }

        let text = Self.normalizeOCRNoise(raw)
        let dateTokens = ExtractionDateParser.findDates(in: text, configuration: configuration)
        let timeTokens = ExtractionTimeParser.findTimes(in: text)

        let dateState = Self.selectDateState(from: dateTokens, in: text)
        let selectedDateRange: NSRange? = {
            let matching: [ExtractedDateToken]
            switch dateState {
            case .resolved(let value):
                matching = dateTokens.filter { $0.components == value }
            case .ambiguous(let candidates, _):
                matching = dateTokens.filter { token in
                    candidates.contains {
                        $0.year == token.components.year
                            && $0.month == token.components.month
                            && $0.day == token.components.day
                    }
                }
            case .missing:
                return nil
            }
            guard !matching.isEmpty else { return nil }
            return matching.max(by: {
                Self.dateAssociationScore(for: $0, in: text) < Self.dateAssociationScore(for: $1, in: text)
            })?.range
        }()

        let timeState = Self.selectTimeState(
            from: timeTokens,
            in: text,
            selectedDateRange: selectedDateRange
        )

        let consumedRanges = Self.consumedRanges(
            dateTokens: dateTokens,
            dateState: dateState,
            timeTokens: timeTokens,
            timeState: timeState
        )

        let (title, titleWasFallback) = Self.extractTitle(from: text, consumedRanges: consumedRanges)
        let note = Self.extractNote(from: text, title: title, consumedRanges: consumedRanges)
        let person = Self.extractPerson(from: text)
        let context = Self.extractContext(from: text)
        let recurrence = Self.extractRecurrence(from: text)

        return ReminderDraft(
            title: title,
            titleWasFallback: titleWasFallback,
            dateState: dateState,
            timeState: timeState,
            note: note,
            personName: person,
            contextName: context,
            personID: nil,
            contextID: nil,
            proposedRecurrence: recurrence,
            timeZoneIdentifier: configuration.timeZone.identifier,
            localeIdentifier: configuration.locale.identifier,
            sourceText: result.fullText
        )
    }

    // MARK: - Date / time selection

    private static func selectDateState(
        from tokens: [ExtractedDateToken],
        in text: String
    ) -> ExtractionFieldState<DateComponents> {
        guard !tokens.isEmpty else { return .missing }

        // A single structurally ambiguous numeric date → ambiguous for confirmation.
        if tokens.count == 1, let only = tokens.first, only.isStructurallyAmbiguous {
            var candidates = [only.components]
            if let alt = only.alternateComponents { candidates.append(alt) }
            return .ambiguous(candidates: candidates, rawSnippet: only.rawSnippet)
        }

        if tokens.count == 1, let only = tokens.first, !only.isStructurallyAmbiguous {
            return .resolved(only.components)
        }

        // Score by local context + UI-noise penalties (prefer association over first match).
        let scored: [(ExtractedDateToken, Int)] = tokens.map { token in
            (token, dateAssociationScore(for: token, in: text))
        }
        let maxScore = scored.map(\.1).max() ?? 0
        let leaders = scored.filter { $0.1 == maxScore }.map(\.0)

        if leaders.count == 1, let best = leaders.first, maxScore > 0, !best.isStructurallyAmbiguous {
            return .resolved(best.components)
        }

        // Unique components among all tokens and no structural ambiguity.
        let uniqued = uniqueDateComponents(tokens.map(\.components))
        if uniqued.count == 1, tokens.allSatisfy({ !$0.isStructurallyAmbiguous }) {
            return .resolved(uniqued[0])
        }

        // Multiple distinct event dates without a clear winner.
        let candidateComponents = uniqueDateComponents(tokens.map(\.components))
        let snippet = tokens.map(\.rawSnippet).joined(separator: "; ")
        return .ambiguous(candidates: candidateComponents, rawSnippet: snippet)
    }

    private static func selectTimeState(
        from tokens: [ExtractedTimeToken],
        in text: String,
        selectedDateRange: NSRange?
    ) -> ExtractionFieldState<DateComponents> {
        guard !tokens.isEmpty else { return .missing }

        if tokens.count == 1 {
            let only = tokens[0]
            // Still reject a lone UI-looking timestamp when there is stronger schedule context elsewhere
            // is handled by multi-time path; a single time remains resolved.
            _ = only
            return .resolved(tokens[0].components)
        }

        // Hard preference: time on the *same line* as appointment/meeting (avoid cross-line bleed).
        let appointmentLinked = tokens.filter { token in
            let line = lineContaining(range: token.range, in: text).lowercased()
            return containsScheduleKeyword(line)
        }
        if appointmentLinked.count == 1 {
            return .resolved(appointmentLinked[0].components)
        }

        let scored: [(ExtractedTimeToken, Int)] = tokens.map { token in
            (token, timeAssociationScore(for: token, in: text, selectedDateRange: selectedDateRange))
        }

        let maxScore = scored.map(\.1).max() ?? Int.min
        let leaders = scored.filter { $0.1 == maxScore }.map(\.0)
        // Require a clear positive association; otherwise mark ambiguous rather than guessing.
        if leaders.count == 1, maxScore > 0 {
            return .resolved(leaders[0].components)
        }

        let uniqued = uniqueTimeComponents(tokens.map(\.components))
        if uniqued.count == 1 {
            return .resolved(uniqued[0])
        }

        return .ambiguous(
            candidates: uniqued,
            rawSnippet: tokens.map(\.rawSnippet).joined(separator: "; ")
        )
    }

    private static func dateAssociationScore(for token: ExtractedDateToken, in text: String) -> Int {
        var score = contextScore(for: token.range, in: text)
        let line = lineContaining(range: token.range, in: text)
        let lower = line.lowercased()
        let raw = token.rawSnippet.lowercased()

        if containsScheduleKeyword(lower) {
            score += 12
        }
        if lower.range(of: #"\b(at|@|,)\s*\d"#, options: .regularExpression) != nil {
            score += 4
        }

        // Relative dates in schedule sentences are strong; bare chat-header relatives are weak.
        if raw == "tomorrow" || raw == "today" || raw == "yesterday" {
            if containsScheduleKeyword(lower) {
                score += 14
            }
            if isChatHeaderRelativeLine(line) {
                score -= 18
            } else if looksLikeDateOrTimeOnly(line) {
                score -= 10
            }
        }
        return score
    }

    private static func timeAssociationScore(
        for token: ExtractedTimeToken,
        in text: String,
        selectedDateRange: NSRange?
    ) -> Int {
        var score = 0
        let line = lineContaining(range: token.range, in: text)
        let lower = line.lowercased()

        if let selectedDateRange {
            if rangesShareLine(token.range, selectedDateRange, in: text) {
                score += 14
            } else {
                let distance = abs(token.range.location - selectedDateRange.location)
                if distance < 40 { score += 8 }
                else if distance < 120 { score += 3 }
            }
        }

        if looksLikeMessageTimestampLine(line) {
            score -= 22
        }
        if lower.contains("open") || lower.contains("hours") {
            score -= 8
        }
        if containsScheduleKeyword(lower) {
            score += 12
        }
        // "at 4 PM", "tomorrow, 4 PM", "tomorrow @ 4 PM"
        if hasScheduleTimeConnector(before: token.range, in: text) {
            score += 10
        } else if lower.range(of: #"\bat\s+\d"#, options: .regularExpression) != nil {
            score += 4
        }
        score += contextScore(for: token.range, in: text)
        return score
    }

    private static func contextScore(for range: NSRange, in text: String) -> Int {
        let window = surroundingText(around: range, in: text, pad: 48).lowercased()
        var score = 0
        let positive = [
            "appointment", "meeting", "due", "deadline", "event", "schedule",
            "follow-up", "follow up", "remind", "at "
        ]
        let negative = ["previous", "prior", "last date", "registration", "opened", "opens"]
        for word in positive where window.contains(word) { score += 5 }
        for word in negative where window.contains(word) { score -= 5 }
        return score
    }

    private static func containsScheduleKeyword(_ lowercasedLine: String) -> Bool {
        let keywords = [
            "appointment", "meeting", "due", "deadline", "event", "schedule",
            "follow-up", "follow up", "remind", "visit", "call", "exam", "submit"
        ]
        return keywords.contains { lowercasedLine.contains($0) }
    }

    private static func hasScheduleTimeConnector(before range: NSRange, in text: String) -> Bool {
        let ns = text as NSString
        let start = max(0, range.location - 18)
        let prefix = ns.substring(with: NSRange(location: start, length: range.location - start)).lowercased()
        return prefix.range(of: #"(?:at|@|,)\s*$"#, options: .regularExpression) != nil
            || prefix.range(of: #"(?:tomorrow|today|yesterday)\s*(?:at|@|,)?\s*$"#, options: .regularExpression) != nil
    }

    private static func rangesShareLine(_ a: NSRange, _ b: NSRange, in text: String) -> Bool {
        lineRange(for: a, in: text) == lineRange(for: b, in: text)
    }

    private static func lineRange(for range: NSRange, in text: String) -> NSRange {
        let ns = text as NSString
        guard range.location != NSNotFound, ns.length > 0 else {
            return NSRange(location: NSNotFound, length: 0)
        }
        var start = min(max(0, range.location), ns.length)
        while start > 0 {
            let previous = ns.substring(with: NSRange(location: start - 1, length: 1))
            if previous == "\n" { break }
            start -= 1
        }
        var end = min(ns.length, max(range.location, 0) + max(range.length, 0))
        while end < ns.length {
            let next = ns.substring(with: NSRange(location: end, length: 1))
            if next == "\n" { break }
            end += 1
        }
        return NSRange(location: start, length: max(0, end - start))
    }

    /// Chat UI lines such as "Yesterday 10:31 AM" / "Today 9:00 AM".
    private static func looksLikeMessageTimestampLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if isChatHeaderRelativeLine(trimmed) { return true }

        let lower = trimmed.lowercased()
        if containsScheduleKeyword(lower) { return false }

        let times = ExtractionTimeParser.findTimes(in: trimmed)
        guard !times.isEmpty else { return false }

        let ns = trimmed as NSString
        var covered = Array(repeating: false, count: ns.length)
        for token in times {
            mark(&covered, range: token.range, length: ns.length)
        }
        for index in 0..<ns.length {
            let scalar = UnicodeScalar(ns.character(at: index))!
            if CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet(charactersIn: ",.-/").contains(scalar) {
                covered[index] = true
            }
        }
        // Allow "today"/"yesterday" labels around a time as UI chrome.
        for word in ["today", "yesterday"] {
            if let range = lower.range(of: word) {
                let nsRange = NSRange(range, in: lower)
                mark(&covered, range: nsRange, length: ns.length)
            }
        }
        return covered.allSatisfy(\.self)
    }

    private static func isChatHeaderRelativeLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "today" || trimmed == "yesterday" || trimmed == "tomorrow" {
            return true
        }
        // "Yesterday 10:31 AM" — relative label + time only.
        let withoutRelative = trimmed
            .replacingOccurrences(of: "yesterday", with: "")
            .replacingOccurrences(of: "today", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if withoutRelative.isEmpty { return true }
        if (trimmed.hasPrefix("yesterday") || trimmed.hasPrefix("today")),
           looksLikeDateOrTimeOnly(withoutRelative) || ExtractionTimeParser.findTimes(in: withoutRelative).count == 1,
           !containsScheduleKeyword(trimmed) {
            let times = ExtractionTimeParser.findTimes(in: trimmed)
            return !times.isEmpty && !containsScheduleKeyword(trimmed)
        }
        return false
    }

    private static func surroundingText(around range: NSRange, in text: String, pad: Int) -> String {
        let ns = text as NSString
        let start = max(0, range.location - pad)
        let end = min(ns.length, range.location + range.length + pad)
        return ns.substring(with: NSRange(location: start, length: end - start))
    }

    private static func lineContaining(range: NSRange, in text: String) -> String {
        let lr = lineRange(for: range, in: text)
        guard lr.location != NSNotFound else { return "" }
        return (text as NSString).substring(with: lr)
    }

    // MARK: - Title / note / person

    private static func extractTitle(
        from text: String,
        consumedRanges: [NSRange]
    ) -> (String, Bool) {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let candidates = lines.filter { line in
            if isMostlyConsumed(line: line, in: text, consumedRanges: consumedRanges) { return false }
            if looksLikeDateOrTimeOnly(line) { return false }
            if isGenericUIOrMetadataLine(line) { return false }
            if line.count < 2 { return false }
            // Long conversational paragraphs are poor titles.
            if line.count > 120 { return false }
            return true
        }

        // Prefer short schedule/action lines over chrome or chatter.
        let scored: [(String, Int)] = candidates.map { line in
            var score = 0
            let lower = line.lowercased()
            if containsScheduleKeyword(lower) { score += 20 }
            if ExtractionDateParser.findDates(
                in: line,
                configuration: ExtractionConfiguration(
                    referenceDate: Date(timeIntervalSince1970: 1_786_291_200),
                    timeZone: TimeZone(secondsFromGMT: 0)!,
                    locale: Locale(identifier: "en_GB")
                )
            ).contains(where: {
                let raw = $0.rawSnippet.lowercased()
                return raw == "tomorrow" || raw == "today" || raw == "yesterday"
            }) {
                score += 6
            }
            if !ExtractionTimeParser.findTimes(in: line).isEmpty, containsScheduleKeyword(lower) {
                score += 4
            }
            // Prefer concise titles.
            if line.count <= 48 { score += 3 }
            else if line.count > 80 { score -= 3 }
            // Soft penalty for bare single-token lines without schedule cues (often UI senders).
            let words = line.split(whereSeparator: { $0.isWhitespace })
            if words.count == 1, !containsScheduleKeyword(lower) {
                score -= 6
            }
            return (line, score)
        }

        if let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 {
            return (trimTitle(best.0), false)
        }

        // Fallback: first short non-metadata line.
        if let first = candidates.first(where: { $0.count <= 80 }) {
            return (trimTitle(first), false)
        }

        return (ReminderDraft.fallbackTitle, true)
    }

    private static func extractNote(
        from text: String,
        title: String,
        consumedRanges: [NSRange]
    ) -> String? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Prefer a short supporting block near the title — never dump full OCR.
        let titleIndex = lines.firstIndex { line in
            line.caseInsensitiveCompare(title) == .orderedSame
                || trimTitle(line).caseInsensitiveCompare(title) == .orderedSame
                || line.localizedCaseInsensitiveContains(title)
        }

        var supporting: [String] = []
        if let titleIndex {
            let window = lines.suffix(from: min(lines.count, titleIndex + 1)).prefix(4)
            for line in window {
                if !isViableNoteLine(line, title: title, text: text, consumedRanges: consumedRanges) {
                    continue
                }
                supporting.append(line)
                if supporting.count >= 2 { break }
            }
        }

        if supporting.isEmpty {
            // No clear nearby note — do not assemble distant leftovers into a huge note.
            return nil
        }

        let joined = supporting.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if joined.count > 240 {
            return nil
        }
        return joined.isEmpty ? nil : joined
    }

    private static func isViableNoteLine(
        _ line: String,
        title: String,
        text: String,
        consumedRanges: [NSRange]
    ) -> Bool {
        if line.caseInsensitiveCompare(title) == .orderedSame { return false }
        if looksLikeDateOrTimeOnly(line) { return false }
        if isMostlyConsumed(line: line, in: text, consumedRanges: consumedRanges) { return false }
        if isGenericUIOrMetadataLine(line) { return false }
        if looksLikeMessageTimestampLine(line) { return false }
        let lower = line.lowercased()
        if lower == "today" || lower == "tomorrow" || lower == "yesterday" { return false }
        // Skip tiny conversational acknowledgements without substance.
        if line.count < 8 { return false }
        if line.count > 160 { return false }
        return true
    }

    /// Generic chrome / metadata — not app-specific extraction rules.
    private static func isGenericUIOrMetadataLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if isChatHeaderRelativeLine(trimmed) { return true }
        if looksLikeMessageTimestampLine(trimmed) { return true }

        // Short chrome labels commonly OCR'd from system UI (generic, not product logic).
        let chromeExact: Set<String> = [
            "whatsapp", "messages", "message", "imessage", "telegram", "signal",
            "mail", "gmail", "inbox", "notes", "note", "photos", "camera",
            "search", "back", "edit", "done", "cancel", "ok", "okay", "thanks",
            "thank you", "delivered", "read", "online", "typing", "status",
            "calls", "chats", "chat", "settings", "today", "yesterday"
        ]
        if chromeExact.contains(lower) { return true }

        if lower.hasPrefix("@"), trimmed.count <= 40 { return true }
        if lower.range(of: #"^https?://"#, options: .regularExpression) != nil { return true }
        if lower.range(of: #"^www\."#, options: .regularExpression) != nil { return true }
        if lower.range(of: #"^\+?\d[\d\s\-()]{6,}\d$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func extractPerson(from text: String) -> String? {
        // Conservative: Name's … — skip Dr./Mr./Mrs./Ms. titles as "person".
        let pattern = #"\b(?!Dr|Mr|Mrs|Ms|Prof)([A-Z][a-z]+)'s\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2
        else { return nil }
        let name = ns.substring(with: match.range(at: 1))
        let blocked = ["Today", "Tomorrow", "Yesterday", "Doctor", "Dentist", "Parent", "Teacher"]
        if blocked.contains(name) { return nil }
        return name
    }

    private static func extractContext(from text: String) -> String? {
        // Extremely conservative: only explicit labeled contexts.
        let pattern = #"(?i)\bcontext\s*:\s*([A-Za-z][A-Za-z0-9 \-]{1,40})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2
        else { return nil }
        let value = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func extractRecurrence(from text: String) -> DraftRecurrenceHint? {
        let lower = text.lowercased()
        if lower.contains("every year") || lower.contains("annually") || lower.contains("annual ") {
            return .yearly
        }
        if lower.contains("every monday") || lower.contains("every week") || lower.contains("weekly") {
            return .weekly
        }
        return nil
    }

    // MARK: - Helpers

    /// Light OCR noise normalization only — never invents missing content.
    static func normalizeOCRNoise(_ text: String) -> String {
        var result = text
        // Common Vision confusion: PN → PM when preceded by a time-like digit.
        if let regex = try? NSRegularExpression(pattern: #"(\d)\s*[Pp][Nn]\b"#) {
            let ns = result as NSString
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(location: 0, length: ns.length),
                withTemplate: "$1 PM"
            )
        }
        // Collapse excessive spaces but keep newlines.
        let lines = result.components(separatedBy: .newlines).map { line in
            line.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        return lines.joined(separator: "\n")
    }

    private static func consumedRanges(
        dateTokens: [ExtractedDateToken],
        dateState: ExtractionFieldState<DateComponents>,
        timeTokens: [ExtractedTimeToken],
        timeState: ExtractionFieldState<DateComponents>
    ) -> [NSRange] {
        var ranges: [NSRange] = []
        switch dateState {
        case .resolved(let value):
            if let token = dateTokens.first(where: { $0.components == value }) {
                ranges.append(token.range)
            }
        case .ambiguous:
            ranges.append(contentsOf: dateTokens.map(\.range))
        case .missing:
            break
        }
        switch timeState {
        case .resolved(let value):
            if let token = timeTokens.first(where: { $0.components == value }) {
                ranges.append(token.range)
            }
        case .ambiguous:
            ranges.append(contentsOf: timeTokens.map(\.range))
        case .missing:
            break
        }
        return ranges
    }

    private static func isMostlyConsumed(line: String, in text: String, consumedRanges: [NSRange]) -> Bool {
        guard let lineRange = text.range(of: line) else { return false }
        let nsRange = NSRange(lineRange, in: text)
        let covered = consumedRanges.reduce(0) { partial, range in
            partial + NSIntersectionRange(nsRange, range).length
        }
        return covered >= max(1, nsRange.length - 2)
    }

    private static func looksLikeDateOrTimeOnly(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower == "today" || lower == "tomorrow" || lower == "yesterday" { return true }

        // Fixed reference used only to detect whether a *line* is structurally date/time-only.
        let probeConfig = ExtractionConfiguration(
            referenceDate: Date(timeIntervalSince1970: 1_786_291_200), // 2026-08-10 UTC
            timeZone: TimeZone(secondsFromGMT: 0)!,
            locale: Locale(identifier: "en_GB")
        )
        let dates = ExtractionDateParser.findDates(in: trimmed, configuration: probeConfig)
        let times = ExtractionTimeParser.findTimes(in: trimmed)
        guard !dates.isEmpty || !times.isEmpty else { return false }

        let ns = trimmed as NSString
        var covered = Array(repeating: false, count: ns.length)
        for token in dates {
            mark(&covered, range: token.range, length: ns.length)
        }
        for token in times {
            mark(&covered, range: token.range, length: ns.length)
        }
        for index in 0..<ns.length {
            let scalar = UnicodeScalar(ns.character(at: index))!
            if CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet(charactersIn: ",.-/").contains(scalar) {
                covered[index] = true
            }
        }
        return covered.allSatisfy(\.self)
    }

    private static func mark(_ covered: inout [Bool], range: NSRange, length: Int) {
        guard range.location != NSNotFound else { return }
        let start = max(0, range.location)
        let end = min(length, range.location + range.length)
        if start < end {
            for index in start..<end {
                covered[index] = true
            }
        }
    }

    private static func trimTitle(_ line: String) -> String {
        var title = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let probeConfig = ExtractionConfiguration(
            referenceDate: Date(timeIntervalSince1970: 1_786_291_200), // 2026-08-10 UTC
            timeZone: TimeZone(secondsFromGMT: 0)!,
            locale: Locale(identifier: "en_GB")
        )
        let dates = ExtractionDateParser.findDates(in: title, configuration: probeConfig)
        let times = ExtractionTimeParser.findTimes(in: title)
        if !dates.isEmpty || !times.isEmpty {
            let ns = title as NSString
            var covered = Array(repeating: false, count: ns.length)
            for token in dates { mark(&covered, range: token.range, length: ns.length) }
            for token in times { mark(&covered, range: token.range, length: ns.length) }
            // Also mark schedule connectors adjacent to removed spans.
            let lower = title.lowercased() as NSString
            for word in [" at ", " on ", " due ", " @ ", ",", " , "] {
                let search = NSRange(location: 0, length: lower.length)
                var cursor = search
                while true {
                    let found = lower.range(of: word, options: [.caseInsensitive], range: cursor)
                    if found.location == NSNotFound { break }
                    mark(&covered, range: found, length: ns.length)
                    let next = found.location + max(found.length, 1)
                    if next >= lower.length { break }
                    cursor = NSRange(location: next, length: lower.length - next)
                }
            }
            var units: [unichar] = []
            units.reserveCapacity(ns.length)
            for index in 0..<ns.length where !covered[index] {
                units.append(ns.character(at: index))
            }
            title = String(utf16CodeUnits: units, count: units.count)
        }

        if let regex = try? NSRegularExpression(
            pattern: #"\s+(on|at|due|@)\s+.+$"#,
            options: [.caseInsensitive]
        ) {
            let ns = title as NSString
            title = regex.stringByReplacingMatches(
                in: title,
                range: NSRange(location: 0, length: ns.length),
                withTemplate: ""
            )
        }
        title = title
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-–:, "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? ReminderDraft.fallbackTitle : title
    }

    private static func uniqueDateComponents(_ items: [DateComponents]) -> [DateComponents] {
        var result: [DateComponents] = []
        for item in items {
            let normalized = DateComponents(year: item.year, month: item.month, day: item.day)
            if !result.contains(normalized) {
                result.append(normalized)
            }
        }
        return result
    }

    private static func uniqueTimeComponents(_ items: [DateComponents]) -> [DateComponents] {
        var result: [DateComponents] = []
        for item in items {
            let normalized = DateComponents(hour: item.hour, minute: item.minute ?? 0)
            if !result.contains(normalized) {
                result.append(normalized)
            }
        }
        return result
    }
}
