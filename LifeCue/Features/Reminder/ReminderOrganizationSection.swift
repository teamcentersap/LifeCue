import SwiftUI

/// Compact optional Person / Context organization for Add / Edit / Review forms.
///
/// Four explicit `NavigationLink` destinations (never shared / never switched):
/// 1. For → `PersonSelectionView`
/// 2. Context → `ContextSelectionView`
/// 3. Add Person → `QuickAddPersonView`
/// 4. Add Context → `QuickAddContextView`
///
/// Top-level People / Contexts screens keep their own single-level sheets.
struct ReminderOrganizationSection: View {
    @Binding var personID: UUID?
    @Binding var contextID: UUID?
    let personService: PersonService
    let contextService: ContextService

    @State private var people: [Person] = []
    @State private var contexts: [ReminderContext] = []

    var body: some View {
        Section {
            NavigationLink {
                PersonSelectionView(
                    personService: personService,
                    selectedPersonID: personID
                ) { selected in
                    personID = selected
                    reloadPeople()
                    reloadContexts()
                }
            } label: {
                HStack {
                    Text("For")
                    Spacer()
                    Text(selectedPersonLabel)
                        .foregroundStyle(LifeCueTheme.secondaryText)
                }
            }
            .accessibilityLabel("For")
            .accessibilityValue(selectedPersonLabel)

            NavigationLink {
                ContextSelectionView(
                    contextService: contextService,
                    personService: personService,
                    personID: personID,
                    selectedContextID: contextID
                ) { selected in
                    contextID = selected
                    reloadContexts()
                }
            } label: {
                HStack {
                    Text("Context")
                    Spacer()
                    Text(selectedContextLabel)
                        .foregroundStyle(LifeCueTheme.secondaryText)
                }
            }
            .accessibilityLabel("Context")
            .accessibilityValue(selectedContextLabel)

            NavigationLink("Add Person") {
                QuickAddPersonView(personService: personService) { person in
                    personID = ReminderOrganizationSelection.selectionAfterCreatingPerson(person)
                    reloadPeople()
                    reloadContexts()
                }
            }

            NavigationLink("Add Context") {
                QuickAddContextView(
                    contextService: contextService,
                    personService: personService,
                    preferredPersonID: personID
                ) { context in
                    contextID = ReminderOrganizationSelection.selectionAfterCreatingContext(context)
                    reloadContexts()
                }
            }
        } header: {
            Text("Organize (optional)")
        } footer: {
            Text("People and contexts are optional. Leave blank if you don’t need them.")
                .font(.footnote)
        }
        .onAppear {
            reloadPeople()
            reloadContexts()
        }
        .onChange(of: personID) { _, newPersonID in
            contextID = ReminderOrganizationSelection.reconciledContextID(
                selectedContextID: contextID,
                newPersonID: newPersonID,
                resolveContext: { id in try? contextService.context(id: id) }
            )
            reloadContexts()
        }
    }

    private var selectedPersonLabel: String {
        guard let personID,
              let person = people.first(where: { $0.id == personID })
                ?? (try? personService.person(id: personID)) else {
            return "No person"
        }
        if let relationship = person.relationship, !relationship.isEmpty {
            return "\(person.name) (\(relationship))"
        }
        return person.name
    }

    private var selectedContextLabel: String {
        guard let contextID,
              let context = contexts.first(where: { $0.id == contextID })
                ?? (try? contextService.context(id: contextID)) else {
            return "No context"
        }
        return ReminderOrganizationDataLoading.contextLabel(context, personService: personService)
    }

    private func reloadPeople() {
        people = (try? ReminderOrganizationDataLoading.loadPeople(
            personService: personService,
            selectedPersonID: personID
        )) ?? []
    }

    private func reloadContexts() {
        contexts = (try? ReminderOrganizationDataLoading.loadContexts(
            contextService: contextService,
            personID: personID,
            selectedContextID: contextID
        )) ?? []
    }
}

// MARK: - Data loading (testable, shared with selection screens)

@MainActor
enum ReminderOrganizationDataLoading {
    static func loadPeople(
        personService: PersonService,
        selectedPersonID: UUID?
    ) throws -> [Person] {
        var loaded = try personService.allPeople()
        if let selectedPersonID,
           let current = try personService.person(id: selectedPersonID),
           !loaded.contains(where: { $0.id == current.id }) {
            loaded.insert(current, at: 0)
        }
        return loaded
    }

    static func loadContexts(
        contextService: ContextService,
        personID: UUID?,
        selectedContextID: UUID?
    ) throws -> [ReminderContext] {
        var loaded = try contextService.contexts(forPersonID: personID, includeGlobal: true)
        if let selectedContextID,
           let current = try contextService.context(id: selectedContextID),
           !loaded.contains(where: { $0.id == current.id }) {
            loaded.insert(current, at: 0)
        }
        return loaded
    }

    static func contextLabel(_ context: ReminderContext, personService: PersonService) -> String {
        if context.isGlobal { return context.name }
        if let personID = context.personID,
           let person = try? personService.person(id: personID) {
            return "\(person.name): \(context.name)"
        }
        return context.name
    }
}

// MARK: - Presentation / destination contract (no shared navigation switch)

/// Destination view type for each organization action — documentation + tests only.
/// UI uses four separate `NavigationLink`s; never a shared `navigationDestination` switch.
enum ReminderOrganizationDestination: String, Equatable {
    case personSelection = "PersonSelectionView"
    case contextSelection = "ContextSelectionView"
    case addPerson = "QuickAddPersonView"
    case addContext = "QuickAddContextView"
}

enum OrganizationCreationPresentation: Equatable {
    case navigationPush
    case sheet
}

enum OrganizationSelectionPresentation: Equatable {
    case navigationLinkPicker
    case menu
    case dedicatedNavigationLink

    static var preferredForReminderForms: OrganizationSelectionPresentation {
        .dedicatedNavigationLink
    }

    static var preferredCreationPresentation: OrganizationCreationPresentation {
        .navigationPush
    }
}

enum ReminderOrganizationSelection {
    static func reconciledContextID(
        selectedContextID: UUID?,
        newPersonID: UUID?,
        resolveContext: (UUID) -> ReminderContext?
    ) -> UUID? {
        guard let selectedContextID else { return nil }
        guard let context = resolveContext(selectedContextID) else { return selectedContextID }
        if let owner = context.personID, owner != newPersonID {
            return nil
        }
        return selectedContextID
    }

    static func selectionAfterCreatingPerson(_ person: Person) -> UUID {
        person.id
    }

    static func selectionAfterCreatingContext(_ context: ReminderContext) -> UUID {
        context.id
    }

    /// Maps intent → destination type for tests. Not used by SwiftUI navigation.
    static func destination(for intent: ReminderOrganizationIntent) -> ReminderOrganizationDestination {
        switch intent {
        case .selectPerson: return .personSelection
        case .selectContext: return .contextSelection
        case .createPerson: return .addPerson
        case .createContext: return .addContext
        }
    }
}

enum ReminderOrganizationIntent: Equatable {
    case selectPerson
    case selectContext
    case createPerson
    case createContext
}

// MARK: - Selection views (load from services)

/// Person selection list — loads persisted active People from `PersonService`.
struct PersonSelectionView: View {
    let personService: PersonService
    let selectedPersonID: UUID?
    var onSelect: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var people: [Person] = []

    var body: some View {
        List {
            Button {
                onSelect(nil)
                dismiss()
            } label: {
                HStack {
                    Text("No person")
                    Spacer()
                    if selectedPersonID == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .accessibilityLabel("No person")

            ForEach(people) { person in
                Button {
                    onSelect(person.id)
                    dismiss()
                } label: {
                    HStack {
                        Text(person.relationship.map { "\(person.name) (\($0))" } ?? person.name)
                        Spacer()
                        if selectedPersonID == person.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .accessibilityLabel(person.name)
            }
        }
        .navigationTitle("Select Person")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
    }

    private func reload() {
        people = (try? ReminderOrganizationDataLoading.loadPeople(
            personService: personService,
            selectedPersonID: selectedPersonID
        )) ?? []
    }
}

/// Context selection list — loads persisted active Contexts from `ContextService`.
struct ContextSelectionView: View {
    let contextService: ContextService
    let personService: PersonService
    let personID: UUID?
    let selectedContextID: UUID?
    var onSelect: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var contexts: [ReminderContext] = []

    var body: some View {
        List {
            Button {
                onSelect(nil)
                dismiss()
            } label: {
                HStack {
                    Text("No context")
                    Spacer()
                    if selectedContextID == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .accessibilityLabel("No context")

            ForEach(contexts) { context in
                Button {
                    onSelect(context.id)
                    dismiss()
                } label: {
                    HStack {
                        Text(label(context))
                        Spacer()
                        if selectedContextID == context.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .accessibilityLabel(label(context))
            }
        }
        .navigationTitle("Select Context")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
    }

    private func label(_ context: ReminderContext) -> String {
        ReminderOrganizationDataLoading.contextLabel(context, personService: personService)
    }

    private func reload() {
        contexts = (try? ReminderOrganizationDataLoading.loadContexts(
            contextService: contextService,
            personID: personID,
            selectedContextID: selectedContextID
        )) ?? []
    }
}

struct QuickAddPersonView: View {
    let personService: PersonService
    var onCreated: (Person) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var relationship = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("Relationship (optional)", text: $relationship)
        }
        .navigationTitle("Add Person")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .alert("Couldn't add", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        do {
            let person = try personService.create(
                name: name,
                relationship: relationship.isEmpty ? nil : relationship
            )
            onCreated(person)
            dismiss()
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Please try again."
        }
    }
}

struct QuickAddContextView: View {
    let contextService: ContextService
    let personService: PersonService
    var preferredPersonID: UUID?
    var onCreated: (ReminderContext) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var personID: UUID?
    @State private var people: [Person] = []
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("Name", text: $name)
            Picker("Person", selection: $personID) {
                Text("General (no person)").tag(UUID?.none)
                ForEach(people) { person in
                    Text(person.name).tag(Optional(person.id))
                }
            }
        }
        .navigationTitle("Add Context")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            people = (try? personService.allPeople()) ?? []
            personID = preferredPersonID
        }
        .alert("Couldn't add", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        do {
            let context = try contextService.create(name: name, personID: personID)
            onCreated(context)
            dismiss()
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Please try again."
        }
    }
}
