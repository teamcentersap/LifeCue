import SwiftUI

struct ContextsListView: View {
    let contextService: ContextService
    let personService: PersonService
    let reminderService: ReminderService
    let organizationDeletionService: OrganizationDeletionService
    var onDataChanged: () -> Void = {}

    @State private var scope: OrganizationListScope = .default
    @State private var globalContexts: [ReminderContext] = []
    @State private var people: [Person] = []
    @State private var contextsByPerson: [UUID: [ReminderContext]] = [:]
    @State private var showAdd = false
    @State private var errorMessage: String?
    @State private var isListEmpty = false

    var body: some View {
        List {
            Section {
                Picker("Contexts list", selection: $scope) {
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

            if isListEmpty {
                Section {
                    Text(OrganizationListPresentation.emptyContextsMessage(for: scope))
                        .foregroundStyle(LifeCueTheme.secondaryText)
                }
            } else {
                Section("General") {
                    if globalContexts.isEmpty {
                        Text(scope == .active ? "No general contexts yet." : "No archived general contexts.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(globalContexts) { context in
                            contextRow(context)
                        }
                    }
                }

                ForEach(people) { person in
                    if let items = contextsByPerson[person.id], !items.isEmpty {
                        Section(person.name) {
                            ForEach(items) { context in
                                contextRow(context)
                            }
                        }
                    }
                }
            }
        }
        .lifeCueReadableContentWidth()
        .navigationTitle("Contexts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add context")
            }
        }
        .onAppear { reload() }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                QuickAddContextView(
                    contextService: contextService,
                    personService: personService,
                    preferredPersonID: nil
                ) { _ in
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

    @ViewBuilder
    private func contextRow(_ context: ReminderContext) -> some View {
        NavigationLink {
            ContextDetailView(
                context: context,
                contextService: contextService,
                personService: personService,
                reminderService: reminderService,
                organizationDeletionService: organizationDeletionService,
                onChange: {
                    reload()
                    onDataChanged()
                }
            )
        } label: {
            Text(context.name)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if scope == .active {
                Button("Archive", role: .destructive) {
                    archive(context)
                }
            }
        }
        .accessibilityLabel(context.name)
    }

    private func reload() {
        do {
            let allPeople = try personService.allPeople(includeArchived: true)
            let scopedContexts = OrganizationListPresentation.contexts(
                from: try contextService.allContexts(includeArchived: true),
                scope: scope
            )
            globalContexts = scopedContexts.filter(\.isGlobal)

            var grouped: [UUID: [ReminderContext]] = [:]
            var sectionPeople: [Person] = []
            var seen = Set<UUID>()
            for context in scopedContexts where !context.isGlobal {
                guard let personID = context.personID else { continue }
                grouped[personID, default: []].append(context)
                if !seen.contains(personID) {
                    seen.insert(personID)
                    if let person = allPeople.first(where: { $0.id == personID }) {
                        sectionPeople.append(person)
                    } else if let person = try personService.person(id: personID) {
                        sectionPeople.append(person)
                    }
                }
            }
            sectionPeople.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            people = sectionPeople
            contextsByPerson = grouped
            isListEmpty = scopedContexts.isEmpty
        } catch {
            errorMessage = "Couldn't load contexts."
        }
    }

    private func archive(_ context: ReminderContext) {
        do {
            _ = try contextService.archive(id: context.id)
            reload()
            onDataChanged()
        } catch {
            errorMessage = "Couldn't archive."
        }
    }
}

/// Edit / archive / unarchive / delete a Context. Row tap opens this screen — never archives on tap.
struct ContextDetailView: View {
    @State var context: ReminderContext
    let contextService: ContextService
    let personService: PersonService
    let reminderService: ReminderService
    let organizationDeletionService: OrganizationDeletionService
    var onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var personID: UUID?
    @State private var people: [Person] = []
    @State private var reminderCount = 0
    @State private var errorMessage: String?
    @State private var showUnusedDeleteConfirm = false
    @State private var showUsedDeleteConfirm = false
    @State private var pendingDependencies = ContextDeletionDependencies(reminderCount: 0)
    @State private var isDeleting = false

    /// Pure helpers for tests (row action contract).
    enum RowAction: Equatable {
        case openDetail
        case archive
        case unarchive
    }

    static var preferredRowTapAction: RowAction { .openDetail }
    static var preferredExplicitArchiveAction: RowAction { .archive }
    static var preferredExplicitUnarchiveAction: RowAction { .unarchive }

    var body: some View {
        Form {
            Section("Context") {
                TextField("Name", text: $name)
                Picker("Person", selection: $personID) {
                    Text("General (no person)").tag(UUID?.none)
                    ForEach(people) { person in
                        Text(person.name).tag(Optional(person.id))
                    }
                    // Keep currently linked archived person visible for edit.
                    if let personID,
                       !people.contains(where: { $0.id == personID }),
                       let linked = try? personService.person(id: personID) {
                        Text("\(linked.name) (archived)").tag(Optional(linked.id))
                    }
                }
                Button("Save") { save() }
            }
            Section {
                Text("\(reminderCount) reminder\(reminderCount == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }
            if context.isArchived {
                Section {
                    Button("Unarchive Context") { unarchive() }
                } footer: {
                    Text("Restores this context to Active. Its person is not changed.")
                }
            } else {
                Section {
                    Button("Archive Context", role: .destructive) { archive() }
                } footer: {
                    Text("Archiving hides this context from new reminders. Existing reminders are kept.")
                }
            }
            Section {
                Button("Delete Context", role: .destructive) {
                    prepareDelete()
                }
                .disabled(isDeleting)
            } footer: {
                Text("Permanent deletion removes this context. Reminders that use it are deleted only if you confirm.")
            }
        }
        .lifeCueFormContentWidth()
        .navigationTitle(context.name)
        .onAppear {
            name = context.name
            personID = context.personID
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
            OrganizationDeletionPresentation.contextUnusedTitle(),
            isPresented: $showUnusedDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(
                OrganizationDeletionPresentation.contextDeleteActionTitle(dependencies: pendingDependencies),
                role: .destructive
            ) {
                Task { await confirmPermanentDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(OrganizationDeletionPresentation.contextUnusedMessage())
        }
        .confirmationDialog(
            OrganizationDeletionPresentation.contextUsedTitle(),
            isPresented: $showUsedDeleteConfirm,
            titleVisibility: .visible
        ) {
            if !context.isArchived {
                Button("Archive Context") { archive() }
            }
            Button(
                OrganizationDeletionPresentation.contextDeleteActionTitle(dependencies: pendingDependencies),
                role: .destructive
            ) {
                Task { await confirmPermanentDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(OrganizationDeletionPresentation.contextUsedMessage(dependencies: pendingDependencies))
        }
    }

    private func reload() {
        people = (try? personService.allPeople()) ?? []
        reminderCount = ((try? reminderService.allReminders()) ?? [])
            .filter { $0.contextID == context.id }
            .count
    }

    private func save() {
        do {
            var updated = context
            updated.name = name
            updated.personID = personID
            // Preserve optional visual tokens if already set.
            updated.iconName = context.iconName
            updated.colorToken = context.colorToken
            context = try contextService.update(updated)
            onChange()
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Couldn't save."
        }
    }

    private func archive() {
        do {
            context = try contextService.archive(id: context.id)
            onChange()
            dismiss()
        } catch {
            errorMessage = "Couldn't archive."
        }
    }

    private func unarchive() {
        do {
            context = try contextService.unarchive(id: context.id)
            onChange()
        } catch {
            errorMessage = "Couldn't unarchive."
        }
    }

    private func prepareDelete() {
        do {
            let dependencies = try organizationDeletionService.contextDependencies(contextID: context.id)
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
            try await organizationDeletionService.permanentlyDeleteContext(id: context.id)
            onChange()
            dismiss()
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Couldn't delete context."
        }
    }
}
