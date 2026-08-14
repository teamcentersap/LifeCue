import SwiftUI

struct AddReminderView: View {
    let service: ReminderService
    let personService: PersonService
    let contextService: ContextService
    let calendarService: CalendarServing
    var onSaved: () -> Void
    var onCancel: () -> Void

    @State private var title: String = ""
    @State private var eventDate: Date = Date()
    @State private var includeTime = false
    @State private var eventTime: Date = Date()
    @State private var note: String = ""
    @State private var personID: UUID?
    @State private var contextID: UUID?
    @State private var schedule = ReminderScheduleFormModel()
    @State private var selectedCalendarEvent: CalendarEvent?
    @State private var isShowingCalendarPicker = false
    @State private var reminderCalendar: Calendar = Calendar.current
    @State private var errorMessage: String?
    @State private var warningMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("What") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.sentences)
                }

                Section("When") {
                    DatePicker("Date", selection: $eventDate, displayedComponents: .date)
                        .environment(\.timeZone, reminderCalendar.timeZone)
                        .environment(\.calendar, reminderCalendar)
                    if schedule.repeatMode == .once {
                        Toggle("Include time", isOn: $includeTime)
                    }
                    if includeTime || schedule.repeatMode != .once {
                        DatePicker(
                            schedule.repeatMode == .once ? "Time" : "Reminder time",
                            selection: $eventTime,
                            displayedComponents: .hourAndMinute
                        )
                        .environment(\.timeZone, reminderCalendar.timeZone)
                        .environment(\.calendar, reminderCalendar)
                    }
                }

                ReminderScheduleFormSections(
                    model: schedule,
                    showsAtEventToggle: true,
                    scheduleCalendar: reminderCalendar,
                    eventDate: eventDate
                )

                Section("Calendar (optional)") {
                    if let selectedCalendarEvent {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(selectedCalendarEvent.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(LifeCueTheme.primaryText)
                                .lineLimit(2)
                            Text(CalendarEventDisplayFormatter.subtitle(for: selectedCalendarEvent))
                                .font(.footnote)
                                .foregroundStyle(LifeCueTheme.secondaryText)
                            Button("Choose another event") {
                                isShowingCalendarPicker = true
                            }
                            .buttonStyle(.bordered)
                            .padding(.top, 6)
                        }
                    } else {
                        Button("Choose upcoming event (optional)") {
                            isShowingCalendarPicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                }

                ReminderOrganizationSection(
                    personID: $personID,
                    contextID: $contextID,
                    personService: personService,
                    contextService: contextService
                )

                Section("Note") {
                    TextField("Optional note", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .sheet(isPresented: $isShowingCalendarPicker) {
                CalendarEventPickerView(
                    calendarService: calendarService,
                    rangeFrom: reminderCalendar.startOfDay(for: Date()),
                    rangeTo: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date().addingTimeInterval(30 * 86400),
                    onSelect: { event in
                        selectedCalendarEvent = event
                        let prefill = CalendarEventPrefill.makePrefill(from: event)
                        title = prefill.title
                        eventDate = prefill.eventDate
                        includeTime = prefill.includeTime
                        eventTime = prefill.eventTime

                        var newCal = Calendar(identifier: .gregorian)
                        newCal.timeZone = TimeZone(identifier: prefill.reminderTimeZoneIdentifier) ?? .current
                        reminderCalendar = newCal
                    }
                )
            }
            .lifeCueFormContentWidth()
            .navigationTitle("Add Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .alert(
                "Couldn't save",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert(
                "Reminder saved",
                isPresented: Binding(
                    get: { warningMessage != nil },
                    set: { if !$0 { warningMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    warningMessage = nil
                    onSaved()
                }
            } message: {
                Text(warningMessage ?? "")
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let calendar = reminderCalendar
            let eventComponents = Reminder.dateComponents(from: eventDate, calendar: calendar)
            let rules = try schedule.buildRules(eventDate: eventComponents, calendar: calendar)
            let useTime = includeTime || schedule.repeatMode != .once
            let result = try await service.create(
                title: title,
                eventDate: eventDate,
                includeTime: useTime,
                eventTime: eventTime,
                note: note,
                rules: rules,
                timeZoneIdentifier: calendar.timeZone.identifier,
                personID: personID,
                contextID: contextID
            )
            if result.scheduleFailed {
                warningMessage = "The reminder was saved, but notifications could not be scheduled. You can try again later."
            } else {
                onSaved()
            }
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Please check the details."
        } catch {
            errorMessage = "Please check the details."
        }
    }
}
