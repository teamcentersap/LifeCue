import SwiftUI

struct ReminderDetailView: View {
    let reminderID: UUID
    let service: ReminderService
    let personService: PersonService
    let contextService: ContextService
    var onChange: () -> Void

    @State private var reminder: Reminder?
    @State private var showEdit = false
    @State private var showForward = false
    @State private var showDeleteConfirm = false
    @State private var showSnoozeOptions = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let forwardSharingService: ForwardSharingServing

    private var metadata: ReminderMetadataResolver {
        ReminderMetadataResolver(personService: personService, contextService: contextService)
    }

    init(
        reminderID: UUID,
        service: ReminderService,
        personService: PersonService,
        contextService: ContextService,
        forwardSharingService: ForwardSharingServing? = nil,
        onChange: @escaping () -> Void
    ) {
        self.reminderID = reminderID
        self.service = service
        self.personService = personService
        self.contextService = contextService
        self.forwardSharingService = forwardSharingService ?? SystemForwardSharingService()
        self.onChange = onChange
    }

    var body: some View {
        Group {
            if let reminder {
                content(reminder)
            } else {
                ProgressView()
                    .task { await load() }
            }
        }
        .background(LifeCueTheme.background.ignoresSafeArea())
        .navigationTitle("Reminder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit") { showEdit = true }
                    Button("Forward") { showForward = true }
                    if reminder?.status == .active {
                        Button("Snooze") { showSnoozeOptions = true }
                        Button("Complete") { Task { await complete() } }
                    }
                    Button("Delete", role: .destructive) { showDeleteConfirm = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showForward) {
            if let reminder {
                ForwardReminderView(
                    reminder: reminder,
                    initialText: forwardText(for: reminder),
                    sharingService: forwardSharingService,
                    onClose: { showForward = false }
                )
            }
        }
        .sheet(isPresented: $showEdit) {
            if let reminder {
                EditReminderView(
                    service: service,
                    personService: personService,
                    contextService: contextService,
                    reminder: reminder,
                    onSaved: {
                        showEdit = false
                        Task {
                            await load()
                            onChange()
                        }
                    },
                    onCancel: { showEdit = false }
                )
            }
        }
        .confirmationDialog(
            "Delete this reminder?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Snooze",
            isPresented: $showSnoozeOptions,
            titleVisibility: .visible
        ) {
            Button("Later today") { Task { await snooze(.laterToday) } }
            Button("Tomorrow") { Task { await snooze(.tomorrow) } }
            Button("Next week") { Task { await snooze(.nextWeek) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func content(_ reminder: Reminder) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(reminder.title)
                        .font(LifeCueTheme.headlineFont)
                        .foregroundStyle(LifeCueTheme.primaryText)
                    Text(ReminderDisplayFormatter.subtitle(for: reminder))
                        .font(LifeCueTheme.captionFont)
                        .foregroundStyle(LifeCueTheme.secondaryText)
                    Text(statusLabel(for: reminder))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(reminder.status == .completed ? LifeCueTheme.today : LifeCueTheme.upcoming)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .lifeCueCard()

                if let personName = metadata.personName(for: reminder) {
                    metadataCard(title: "For", value: personName)
                }
                if let contextName = metadata.contextName(for: reminder) {
                    metadataCard(title: "Context", value: contextName)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Remind me")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LifeCueTheme.secondaryText)
                    Text(ReminderRuleDisplayFormatter.summary(for: reminder))
                        .font(LifeCueTheme.bodyFont)
                        .foregroundStyle(LifeCueTheme.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .lifeCueCard()

                if reminder.hasNote, let note = reminder.note {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(LifeCueTheme.secondaryText)
                        Text(note)
                            .font(LifeCueTheme.bodyFont)
                            .foregroundStyle(LifeCueTheme.primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lifeCueCard()
                }

                VStack(spacing: 12) {
                    if reminder.status == .active {
                        Button { showSnoozeOptions = true } label: {
                            Label("Snooze", systemImage: "clock")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button { Task { await complete() } } label: {
                            Label("Mark Complete", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(LifeCueTheme.today)
                    }

                    Button(role: .destructive, action: { showDeleteConfirm = true }) {
                        Label("Delete", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
    }

    private func metadataCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LifeCueTheme.secondaryText)
            Text(value)
                .font(LifeCueTheme.bodyFont)
                .foregroundStyle(LifeCueTheme.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lifeCueCard()
    }

    private func forwardText(for reminder: Reminder) -> String {
        ReminderForwardFormatter.makeText(
            for: reminder,
            personName: metadata.personName(for: reminder),
            contextName: metadata.contextName(for: reminder)
        )
    }

    private func statusLabel(for reminder: Reminder) -> String {
        switch reminder.status {
        case .active: return "Active"
        case .completed: return "Completed"
        }
    }

    private func load() async {
        do {
            reminder = try service.reminder(id: reminderID)
            if reminder == nil {
                dismiss()
            }
        } catch {
            errorMessage = "Couldn't load reminder."
        }
    }

    private func complete() async {
        do {
            try await service.complete(id: reminderID)
            await load()
            onChange()
        } catch {
            errorMessage = "Couldn't complete reminder."
        }
    }

    private func delete() async {
        do {
            try await service.delete(id: reminderID)
            onChange()
            dismiss()
        } catch {
            errorMessage = "Couldn't delete reminder."
        }
    }

    private func snooze(_ option: SnoozeOption) async {
        do {
            try await service.snooze(id: reminderID, option: option)
            await load()
            onChange()
        } catch {
            errorMessage = "Couldn't snooze reminder."
        }
    }
}
