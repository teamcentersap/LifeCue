import SwiftUI

struct PeopleListView: View {
    let personService: PersonService
    let contextService: ContextService
    let reminderService: ReminderService
    let organizationDeletionService: OrganizationDeletionService
    var onDataChanged: () -> Void = {}

    @State private var scope: OrganizationListScope = .default
    @State private var people: [Person] = []
    @State private var showAdd = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Picker("People list", selection: $scope) {
                    ForEach(OrganizationListScope.allCases) { segment in
                        Text(segment.title).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .onChange(of: scope) { _, _ in
                    reload()
                }
            }

            Section {
                if people.isEmpty {
                    Text(OrganizationListPresentation.emptyPeopleMessage(for: scope))
                        .foregroundStyle(LifeCueTheme.secondaryText)
                } else {
                    ForEach(people) { person in
                        NavigationLink {
                            PersonDetailView(
                                person: person,
                                personService: personService,
                                contextService: contextService,
                                reminderService: reminderService,
                                organizationDeletionService: organizationDeletionService,
                                onChange: {
                                    reload()
                                    onDataChanged()
                                }
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(person.name)
                                    .font(.body.weight(.semibold))
                                if let relationship = person.relationship {
                                    Text(relationship)
                                        .font(LifeCueTheme.captionFont)
                                        .foregroundStyle(LifeCueTheme.secondaryText)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("People")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add person")
            }
        }
        .onAppear { reload() }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                QuickAddPersonView(personService: personService) { _ in
                    scope = .active
                    reload()
                }
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func reload() {
        do {
            let all = try personService.allPeople(includeArchived: true)
            people = OrganizationListPresentation.people(from: all, scope: scope)
        } catch {
            errorMessage = "Couldn't load people."
        }
    }
}

struct PersonDetailView: View {
    @State var person: Person
    let personService: PersonService
    let contextService: ContextService
    let reminderService: ReminderService
    let organizationDeletionService: OrganizationDeletionService
    var onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var contexts: [ReminderContext] = []
    @State private var reminderCount = 0
    @State private var name: String = ""
    @State private var relationship: String = ""
    @State private var errorMessage: String?
    @State private var showUnusedDeleteConfirm = false
    @State private var showUsedDeleteConfirm = false
    @State private var pendingDependencies = PersonDeletionDependencies(
        reminderCount: 0,
        personalContextCount: 0
    )
    @State private var isDeleting = false

    var body: some View {
        Form {
            Section("Person") {
                TextField("Name", text: $name)
                TextField("Relationship (optional)", text: $relationship)
                Button("Save") { save() }
            }
            Section("Contexts") {
                if contexts.isEmpty {
                    Text("No contexts for this person.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(contexts) { context in
                        Text(context.name)
                    }
                }
            }
            Section {
                Text("\(reminderCount) reminder\(reminderCount == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }
            if person.isArchived {
                Section {
                    Button("Unarchive Person") { unarchive() }
                } footer: {
                    Text("Restores this person to Active. Personal contexts stay archived until you restore them separately.")
                }
            } else {
                Section {
                    Button("Archive Person", role: .destructive) { archive() }
                } footer: {
                    Text("Archiving hides this person from new reminders. Existing reminders are kept.")
                }
            }
            Section {
                Button("Delete Person", role: .destructive) {
                    prepareDelete()
                }
                .disabled(isDeleting)
            } footer: {
                Text("Permanent deletion removes this person and any personal contexts and reminders that belong to them.")
            }
        }
        .navigationTitle(person.name)
        .onAppear {
            name = person.name
            relationship = person.relationship ?? ""
            reload()
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            OrganizationDeletionPresentation.personUnusedTitle(),
            isPresented: $showUnusedDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(
                OrganizationDeletionPresentation.personDeleteActionTitle(dependencies: pendingDependencies),
                role: .destructive
            ) {
                Task { await confirmPermanentDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(OrganizationDeletionPresentation.personUnusedMessage())
        }
        .confirmationDialog(
            OrganizationDeletionPresentation.personUsedTitle(),
            isPresented: $showUsedDeleteConfirm,
            titleVisibility: .visible
        ) {
            if !person.isArchived {
                Button("Archive Person") { archive() }
            }
            Button(
                OrganizationDeletionPresentation.personDeleteActionTitle(dependencies: pendingDependencies),
                role: .destructive
            ) {
                Task { await confirmPermanentDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(OrganizationDeletionPresentation.personUsedMessage(dependencies: pendingDependencies))
        }
    }

    private func reload() {
        // Active personal contexts only — archived contexts stay archived (no cascade display).
        contexts = (try? contextService.contexts(forPersonID: person.id, includeGlobal: false)) ?? []
        reminderCount = ((try? reminderService.allReminders()) ?? [])
            .filter { $0.personID == person.id }
            .count
    }

    private func save() {
        do {
            var updated = person
            updated.name = name
            updated.relationship = relationship
            person = try personService.update(updated)
            onChange()
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Couldn't save."
        }
    }

    private func archive() {
        do {
            person = try personService.archive(id: person.id)
            onChange()
        } catch {
            errorMessage = "Couldn't archive."
        }
    }

    private func unarchive() {
        do {
            person = try personService.unarchive(id: person.id)
            onChange()
        } catch {
            errorMessage = "Couldn't unarchive."
        }
    }

    private func prepareDelete() {
        do {
            let dependencies = try organizationDeletionService.personDependencies(personID: person.id)
            pendingDependencies = dependencies
            if dependencies.isEmpty {
                showUnusedDeleteConfirm = true
            } else {
                showUsedDeleteConfirm = true
            }
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Couldn't prepare deletion."
        }
    }

    private func confirmPermanentDelete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await organizationDeletionService.permanentlyDeletePerson(id: person.id)
            onChange()
            dismiss()
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Couldn't delete person."
        }
    }
}
