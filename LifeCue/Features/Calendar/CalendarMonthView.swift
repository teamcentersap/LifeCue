import SwiftUI
import UIKit

struct CalendarMonthView: View {
    let calendarService: CalendarServing
    let reminderService: ReminderService
    let personService: PersonService
    let contextService: ContextService
    var dataRefreshToken: UUID = UUID()

    @StateObject private var vm: CalendarMonthViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedEvent: CalendarEvent?

    init(
        calendarService: CalendarServing,
        reminderService: ReminderService,
        personService: PersonService,
        contextService: ContextService,
        dataRefreshToken: UUID = UUID()
    ) {
        self.calendarService = calendarService
        self.reminderService = reminderService
        self.personService = personService
        self.contextService = contextService
        self.dataRefreshToken = dataRefreshToken
        _vm = StateObject(
            wrappedValue: CalendarMonthViewModel(
                calendarService: calendarService,
                reminderService: reminderService
            )
        )
    }

    private var metadata: ReminderMetadataResolver {
        ReminderMetadataResolver(personService: personService, contextService: contextService)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    monthHeader
                    weekdayHeader
                    monthGrid
                    eventKitAccessBanner
                    selectedDaySection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .lifeCueCalendarContentWidth()
            }
            .background(LifeCueTheme.background.ignoresSafeArea())
            .navigationTitle("Calendar")
            .navigationDestination(for: UUID.self) { id in
                ReminderDetailView(
                    reminderID: id,
                    service: reminderService,
                    personService: personService,
                    contextService: contextService,
                    onChange: {
                        Task { await vm.refreshOnBecomeActive() }
                    }
                )
            }
            .sheet(item: $selectedEvent) { event in
                CalendarEventDetailView(event: event)
            }
            .task {
                await vm.loadInitial()
            }
            .onChange(of: dataRefreshToken) { _, _ in
                Task { await vm.refreshOnBecomeActive() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await vm.refreshOnBecomeActive() }
            }
        }
    }

    // MARK: - Month chrome

    private var monthHeader: some View {
        HStack {
            Button {
                vm.goToPreviousMonth()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LifeCueTheme.today)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Previous month")

            Spacer()

            VStack(spacing: 4) {
                Text(vm.monthTitle)
                    .font(LifeCueTheme.headlineFont)
                    .foregroundStyle(LifeCueTheme.primaryText)
                Button("Today") {
                    vm.goToCurrentMonth()
                }
                .font(LifeCueTheme.captionFont)
                .foregroundStyle(LifeCueTheme.today)
            }

            Spacer()

            Button {
                vm.goToNextMonth()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LifeCueTheme.today)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Next month")
        }
        .padding(.top, 8)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
            ForEach(Array(vm.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LifeCueTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 6) {
            ForEach(vm.cells) { cell in
                dayCell(cell)
            }
        }
        .lifeCueCard()
    }

    private func dayCell(_ cell: MonthCalendarCell) -> some View {
        let isSelected = vm.selectedDay == cell.day
        let hasReminder = vm.reminderIndicatorDays.contains(cell.day)
        let hasEvent = vm.eventIndicatorDays.contains(cell.day)

        return Button {
            vm.selectDay(cell.day)
        } label: {
            VStack(spacing: 4) {
                Text("\(cell.dayNumber)")
                    .font(.body.weight(cell.isToday ? .semibold : .regular))
                    .foregroundStyle(dayNumberColor(cell: cell, isSelected: isSelected))
                    .frame(width: 32, height: 32)
                    .background {
                        if isSelected {
                            Circle().fill(LifeCueTheme.today.opacity(0.18))
                        } else if cell.isToday {
                            Circle().stroke(LifeCueTheme.today, lineWidth: 1.5)
                        }
                    }

                HStack(spacing: 3) {
                    if hasReminder {
                        Circle()
                            .fill(LifeCueTheme.today)
                            .frame(width: 5, height: 5)
                    }
                    if hasEvent {
                        Circle()
                            .stroke(LifeCueTheme.upcoming, lineWidth: 1.2)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .opacity(cell.isInDisplayedMonth ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: cell, hasReminder: hasReminder, hasEvent: hasEvent))
    }

    private func dayNumberColor(cell: MonthCalendarCell, isSelected: Bool) -> Color {
        if isSelected { return LifeCueTheme.today }
        if cell.isToday { return LifeCueTheme.today }
        return LifeCueTheme.primaryText
    }

    private func accessibilityLabel(for cell: MonthCalendarCell, hasReminder: Bool, hasEvent: Bool) -> String {
        var parts = ["\(cell.dayNumber)"]
        if cell.isToday { parts.append("Today") }
        if hasReminder { parts.append("LifeCue reminder") }
        if hasEvent { parts.append("Calendar event") }
        return parts.joined(separator: ", ")
    }

    // MARK: - EventKit access (non-blocking)

    @ViewBuilder
    private var eventKitAccessBanner: some View {
        switch vm.authorizationStatus {
        case .fullAccess:
            EmptyView()
        case .notDetermined:
            VStack(alignment: .leading, spacing: 10) {
                Text("Show calendar events")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LifeCueTheme.primaryText)
                Text("Optionally include events from your device calendars. LifeCue reminders always stay on this device.")
                    .font(LifeCueTheme.captionFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)
                Button("Allow Calendar Access") {
                    Task { await vm.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
                .tint(LifeCueTheme.today)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LifeCueTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .denied, .restricted:
            VStack(alignment: .leading, spacing: 10) {
                Text("Calendar access unavailable")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LifeCueTheme.primaryText)
                Text("You can continue using LifeCue without Calendar events. Open Settings to enable access.")
                    .font(LifeCueTheme.captionFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)
                HStack {
                    Button("Open Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(LifeCueTheme.today)
                    Button("Not Now") { }
                        .buttonStyle(.bordered)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LifeCueTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .unavailable:
            Text("Calendar access is unavailable on this device.")
                .font(LifeCueTheme.captionFont)
                .foregroundStyle(LifeCueTheme.secondaryText)
        }
    }

    // MARK: - Selected day

    private var selectedDaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(vm.selectedDayTitle.isEmpty ? "Select a date" : vm.selectedDayTitle)
                .font(LifeCueTheme.headlineFont)
                .foregroundStyle(LifeCueTheme.primaryText)

            if let errorMessage = vm.errorMessage {
                Text(errorMessage)
                    .font(LifeCueTheme.captionFont)
                    .foregroundStyle(LifeCueTheme.overdue)
            }

            if vm.isSelectedDayEmpty {
                Text("No reminders or events")
                    .font(LifeCueTheme.bodyFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)
                    .padding(.vertical, 8)
            } else {
                if !vm.selectedReminders.isEmpty {
                    Text("LifeCue")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LifeCueTheme.secondaryText)
                    ForEach(vm.selectedReminders) { reminder in
                        NavigationLink(value: reminder.id) {
                            reminderRow(reminder)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !vm.selectedEvents.isEmpty {
                    Text("Calendar")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(LifeCueTheme.secondaryText)
                        .padding(.top, vm.selectedReminders.isEmpty ? 0 : 8)
                    ForEach(vm.selectedEvents) { event in
                        Button {
                            selectedEvent = event
                        } label: {
                            eventRow(event)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reminderRow(_ reminder: Reminder) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reminder.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(LifeCueTheme.primaryText)
                .multilineTextAlignment(.leading)
            if let time = ReminderDisplayFormatter.timeString(for: reminder) {
                Text(time)
                    .font(LifeCueTheme.captionFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)
            }
            if let subtitle = metadata.compactSubtitle(for: reminder) {
                Text(subtitle)
                    .font(LifeCueTheme.captionFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LifeCueTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(LifeCueTheme.primaryText)
                .multilineTextAlignment(.leading)
            Text(event.calendarName)
                .font(LifeCueTheme.captionFont)
                .foregroundStyle(LifeCueTheme.secondaryText)
            Text(event.isAllDay ? "All day" : (CalendarEventDisplayFormatter.timeString(for: event) ?? ""))
                .font(LifeCueTheme.captionFont)
                .foregroundStyle(LifeCueTheme.secondaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LifeCueTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Lightweight read-only EventKit event detail (no write-back).
struct CalendarEventDetailView: View {
    let event: CalendarEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    LabeledContent("Title", value: event.title)
                    LabeledContent("Date", value: CalendarEventDisplayFormatter.dateString(for: event))
                    if event.isAllDay {
                        LabeledContent("Time", value: "All day")
                    } else if let time = CalendarEventDisplayFormatter.timeString(for: event) {
                        LabeledContent("Time", value: time)
                    }
                    LabeledContent("Calendar", value: event.calendarName)
                }
            }
            .navigationTitle("Calendar Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Presentation contract for tests: reminder rows push the existing detail screen.
enum CalendarMonthReminderNavigation {
    static var detailDestinationName: String { "ReminderDetailView" }
    static var opensExistingReminderDetail: Bool { true }
}
