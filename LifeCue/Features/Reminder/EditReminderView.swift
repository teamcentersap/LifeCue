import SwiftUI

struct EditReminderView: View {
    let service: ReminderService
    let personService: PersonService
    let contextService: ContextService
    let reminder: Reminder
    var onSaved: () -> Void
    var onCancel: () -> Void

    @State private var title: String
    @State private var eventDate: Date
    @State private var includeTime: Bool
    @State private var eventTime: Date
    @State private var note: String
    @State private var personID: UUID?
    @State private var contextID: UUID?
    @State private var schedule: ReminderScheduleFormModel
    @State private var errorMessage: String?
    @State private var warningMessage: String?
    @State private var isSaving = false

    private let reminderCalendar: Calendar

    init(
        service: ReminderService,
        personService: PersonService,
        contextService: ContextService,
        reminder: Reminder,
        onSaved: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.service = service
        self.personService = personService
        self.contextService = contextService
        self.reminder = reminder
        self.onSaved = onSaved
        self.onCancel = onCancel

        let calendar = reminder.calendarInStoredTimeZone()
        self.reminderCalendar = calendar

        _title = State(initialValue: reminder.title)
        _note = State(initialValue: reminder.note ?? "")
        _personID = State(initialValue: reminder.personID)
        _contextID = State(initialValue: reminder.contextID)

        let date = calendar.date(from: Reminder.normalizedDate(reminder.eventDate)) ?? Date()
        _eventDate = State(initialValue: date)

        if let eventTime = reminder.eventTime,
           let hour = eventTime.hour,
           let minute = eventTime.minute {
            var components = Reminder.normalizedDate(reminder.eventDate)
            components.hour = hour
            components.minute = minute
            components.second = 0
            _includeTime = State(initialValue: true)
            _eventTime = State(initialValue: calendar.date(from: components) ?? date)
        } else {
            _includeTime = State(initialValue: false)
            _eventTime = State(initialValue: date)
        }

        let form = ReminderScheduleFormModel()
        form.load(from: reminder, calendar: calendar)
        _schedule = State(initialValue: form)
    }

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
            .lifeCueFormContentWidth()
            .navigationTitle("Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
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
            var updated = reminder
            updated.title = title
            updated.eventDate = Reminder.dateComponents(from: eventDate, calendar: reminderCalendar)
            let useTime = includeTime || schedule.repeatMode != .once
            updated.eventTime = useTime
                ? Reminder.timeComponents(from: eventTime, calendar: reminderCalendar)
                : nil
            updated.timeZoneIdentifier = reminder.timeZoneIdentifier
            updated.note = note
            updated.personID = personID
            updated.contextID = contextID
            updated.rules = try schedule.buildRules(
                eventDate: updated.eventDate,
                calendar: reminderCalendar
            )
            let result = try await service.update(updated)
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
