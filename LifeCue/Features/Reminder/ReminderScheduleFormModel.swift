import SwiftUI

enum ReminderRepeatMode: String, CaseIterable, Identifiable {
    case once
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .once: return "Once"
        case .daily: return "Every day"
        case .weekly: return "Every week"
        case .monthly: return "Every month"
        case .yearly: return "Every year"
        }
    }
}

/// Shared schedule editor state for Add/Edit Reminder (Sprint 6).
@Observable
final class ReminderScheduleFormModel {
    var repeatMode: ReminderRepeatMode = .once
    /// Calendar weekdays 1…7
    var selectedWeekdays: Set<Int> = [2] // Monday default
    var remindAtEvent = true
    var remindTenMinutesBefore = false
    var remindOneHourBefore = false
    var remindOneDayBefore = true
    var remindOneWeekBefore = true
    var useCustomBefore = false
    var customBeforeValue = 2
    var customBeforeUnit: ReminderOffsetUnit = .week
    /// Extra before-event rules that are not represented by the preset toggles / primary custom fields.
    private(set) var additionalBeforeRules: [ReminderRule] = []
    var useDateWindow = false
    var windowStart: Date = Date()
    var windowEnd: Date = Date()
    /// True when Start/End were loaded from a stored reminder window (Edit).
    /// Prevents re-seeding over saved values when Limit dates is toggled.
    private var hasPersistedDateWindow = false

    func load(from reminder: Reminder, calendar: Calendar) {
        additionalBeforeRules = []
        useCustomBefore = false
        customBeforeValue = 2
        customBeforeUnit = .week
        remindTenMinutesBefore = false
        remindOneHourBefore = false
        remindOneDayBefore = false
        remindOneWeekBefore = false
        hasPersistedDateWindow = false

        let standing = reminder.standingRules.filter(\.enabled)
        if let recurring = standing.first(where: { $0.ruleType == .recurring }),
           let recurrence = recurring.recurrence {
            switch recurrence.frequency {
            case .daily: repeatMode = .daily
            case .weekly:
                repeatMode = .weekly
                selectedWeekdays = Set(recurrence.weekdays ?? [2])
            case .monthly: repeatMode = .monthly
            case .yearly: repeatMode = .yearly
            }
            if let window = recurring.dateWindow,
               let start = calendar.date(from: DateComponents(
                year: window.startDate.year,
                month: window.startDate.month,
                day: window.startDate.day,
                hour: 12,
                minute: 0
               )),
               let end = calendar.date(from: DateComponents(
                year: window.endDate.year,
                month: window.endDate.month,
                day: window.endDate.day,
                hour: 12,
                minute: 0
               )) {
                useDateWindow = true
                windowStart = start
                windowEnd = end
                hasPersistedDateWindow = true
            } else {
                useDateWindow = false
            }
        } else {
            repeatMode = .once
            useDateWindow = false
        }

        remindAtEvent = standing.contains { $0.ruleType == .exactAtEvent }
            || standing.contains { $0.ruleType == .recurring }

        let beforeRules = standing.filter { $0.ruleType == .beforeEvent }
        for rule in beforeRules {
            guard let value = rule.offsetValue, let unit = rule.offsetUnit else {
                additionalBeforeRules.append(rule)
                continue
            }
            if value == 10, unit == .minute, !remindTenMinutesBefore {
                remindTenMinutesBefore = true
            } else if value == 1, unit == .hour, !remindOneHourBefore {
                remindOneHourBefore = true
            } else if value == 1, unit == .day, !remindOneDayBefore {
                remindOneDayBefore = true
            } else if value == 1, unit == .week, !remindOneWeekBefore {
                remindOneWeekBefore = true
            } else if !useCustomBefore {
                useCustomBefore = true
                customBeforeValue = value
                customBeforeUnit = unit
            } else {
                // Preserve additional non-preset offsets across edit/save.
                additionalBeforeRules.append(rule)
            }
        }
    }

    /// Turns Limit dates on/off. When enabling a **new** window (no stored window),
    /// seeds Start/End from the reminder event date in `calendar` (reminder scheduling TZ).
    func applyDateWindowEnabled(_ enabled: Bool, eventDate: Date, calendar: Calendar) {
        if enabled && !useDateWindow && !hasPersistedDateWindow {
            seedDateWindow(from: eventDate, calendar: calendar)
        }
        useDateWindow = enabled
    }

    /// Sets Start and End to the same calendar day as `eventDate` (noon anchor, Sprint 6.1 style).
    func seedDateWindow(from eventDate: Date, calendar: Calendar) {
        let day = calendar.startOfDay(for: eventDate)
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = 12
        components.minute = 0
        let anchored = calendar.date(from: components) ?? day
        windowStart = anchored
        windowEnd = anchored
    }

    func buildRules(
        eventDate: DateComponents,
        calendar: Calendar
    ) throws -> [ReminderRule] {
        var rules: [ReminderRule] = []
        var window: ReminderDateWindow?
        if useDateWindow && repeatMode != .once {
            let start = Reminder.dateComponents(from: windowStart, calendar: calendar)
            let end = Reminder.dateComponents(from: windowEnd, calendar: calendar)
            window = ReminderDateWindow(startDate: start, endDate: end)
            try ReminderRuleValidator.validate(window: window!, calendar: calendar)
        }

        switch repeatMode {
        case .once:
            if remindAtEvent {
                rules.append(.exactAtEvent())
            }
        case .daily:
            rules.append(.recurring(.daily(), window: window))
        case .weekly:
            let days = selectedWeekdays.sorted()
            let recurrence = ReminderRecurrence.weekly(weekdays: days)
            try ReminderRuleValidator.validate(recurrence: recurrence)
            rules.append(.recurring(recurrence, window: window))
        case .monthly:
            let day = eventDate.day ?? 1
            let recurrence = ReminderRecurrence.monthly(dayOfMonth: day)
            try ReminderRuleValidator.validate(recurrence: recurrence)
            rules.append(.recurring(recurrence, window: window))
        case .yearly:
            rules.append(.recurring(.yearly(), window: window))
        }

        if remindTenMinutesBefore {
            rules.append(.beforeEvent(value: 10, unit: .minute))
        }
        if remindOneHourBefore {
            rules.append(.beforeEvent(value: 1, unit: .hour))
        }
        if remindOneDayBefore {
            rules.append(.beforeEvent(value: 1, unit: .day))
        }
        if remindOneWeekBefore {
            rules.append(.beforeEvent(value: 1, unit: .week))
        }
        if useCustomBefore, customBeforeValue > 0 {
            rules.append(.beforeEvent(value: customBeforeValue, unit: customBeforeUnit))
        }
        rules.append(contentsOf: additionalBeforeRules.filter {
            $0.ruleType == .beforeEvent && $0.enabled
        })

        try ReminderRuleValidator.validate(rules: rules, calendar: calendar)
        return rules
    }
}

struct ReminderScheduleFormSections: View {
    @Bindable var model: ReminderScheduleFormModel
    var showsAtEventToggle: Bool
    /// Authoritative calendar/timezone for date-window editing (reminder TZ when editing).
    var scheduleCalendar: Calendar
    /// Reminder event date used to seed a newly enabled Limit dates window.
    var eventDate: Date

    var body: some View {
        Section("Repeat") {
            Picker("Remind me", selection: $model.repeatMode) {
                ForEach(ReminderRepeatMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.inline)

            if model.repeatMode == .weekly {
                Text("Repeat on")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ReminderWeekdaySelectorUI.choices, id: \.weekday) { choice in
                            Button {
                                ReminderWeekdaySelectorUI.toggle(
                                    weekday: choice.weekday,
                                    in: &model.selectedWeekdays
                                )
                            } label: {
                                Text(choice.label)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(minWidth: 44, minHeight: 32)
                            }
                            .buttonStyle(.bordered)
                            .tint(
                                model.selectedWeekdays.contains(choice.weekday)
                                    ? LifeCueTheme.today
                                    : .secondary
                            )
                            .accessibilityLabel(choice.accessibilityLabel)
                            .accessibilityAddTraits(
                                model.selectedWeekdays.contains(choice.weekday) ? .isSelected : []
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if model.repeatMode != .once {
                Toggle(
                    "Limit dates",
                    isOn: Binding(
                        get: { model.useDateWindow },
                        set: { model.applyDateWindowEnabled($0, eventDate: eventDate, calendar: scheduleCalendar) }
                    )
                )
                if model.useDateWindow {
                    limitDateRow(title: "Start", selection: $model.windowStart)
                    limitDateRow(title: "End", selection: $model.windowEnd)
                }
            }
        }

        Section("Remind me") {
            if showsAtEventToggle && model.repeatMode == .once {
                Toggle("At the event", isOn: $model.remindAtEvent)
            }
            Toggle("10 minutes before", isOn: $model.remindTenMinutesBefore)
            Toggle("1 hour before", isOn: $model.remindOneHourBefore)
            Toggle("1 day before", isOn: $model.remindOneDayBefore)
            Toggle("1 week before", isOn: $model.remindOneWeekBefore)
            Toggle("Custom before", isOn: $model.useCustomBefore)
            if model.useCustomBefore {
                Stepper("\(model.customBeforeValue)", value: $model.customBeforeValue, in: 1...60)
                Picker("Unit", selection: $model.customBeforeUnit) {
                    Text("Minutes").tag(ReminderOffsetUnit.minute)
                    Text("Hours").tag(ReminderOffsetUnit.hour)
                    Text("Days").tag(ReminderOffsetUnit.day)
                    Text("Weeks").tag(ReminderOffsetUnit.week)
                }
            }
            Text(model.repeatMode == .once
                 ? LifeCueSettings.dateOnlyReminderFootnote
                 : "Repeating reminders use the time you set above.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Compact DatePicker labels flip between short/medium styles (and widths), which also
    /// scrolls the Form. Show LifeCue medium dates ourselves and keep a stable picker hit target.
    private func limitDateRow(title: String, selection: Binding<Date>) -> some View {
        let displayed = ReminderDisplayFormatter.dateString(
            from: selection.wrappedValue,
            calendar: scheduleCalendar
        )
        return HStack {
            Text(title)
            Spacer()
            ZStack(alignment: .trailing) {
                Text(displayed)
                    .foregroundStyle(Color.accentColor)
                    .allowsHitTesting(false)

                DatePicker("", selection: selection, displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.timeZone, scheduleCalendar.timeZone)
                    .environment(\.calendar, scheduleCalendar)
                    // Hide the system short/medium label; keep the control tappable.
                    .colorMultiply(.clear)
                    .frame(width: 140, alignment: .trailing)
                    // Stabilize SwiftUI DatePicker layout when the value changes.
                    .id(selection.wrappedValue)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(displayed)
            .accessibilityAddTraits(.isButton)
        }
    }
}

/// Presentation helpers for weekly multi-day selection.
/// Labels stay single-line (`Mon`…`Sun`); selection values remain Calendar weekdays 1…7.
enum ReminderWeekdaySelectorUI {
    struct Choice: Equatable {
        let weekday: Int
        let label: String
        let accessibilityLabel: String
    }

    static let choices: [Choice] = [
        Choice(weekday: 2, label: "Mon", accessibilityLabel: "Monday"),
        Choice(weekday: 3, label: "Tue", accessibilityLabel: "Tuesday"),
        Choice(weekday: 4, label: "Wed", accessibilityLabel: "Wednesday"),
        Choice(weekday: 5, label: "Thu", accessibilityLabel: "Thursday"),
        Choice(weekday: 6, label: "Fri", accessibilityLabel: "Friday"),
        Choice(weekday: 7, label: "Sat", accessibilityLabel: "Saturday"),
        Choice(weekday: 1, label: "Sun", accessibilityLabel: "Sunday")
    ]

    /// Same multi-select rules as before: toggle freely, but keep at least one day selected.
    static func toggle(weekday: Int, in selected: inout Set<Int>) {
        if selected.contains(weekday) {
            if selected.count > 1 {
                selected.remove(weekday)
            }
        } else {
            selected.insert(weekday)
        }
    }
}
