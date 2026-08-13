import SwiftUI

struct HomeView: View {
    @Bindable var viewModel: ReminderListViewModel
    let reminderService: ReminderService
    let personService: PersonService
    let contextService: ContextService
    @Bindable var notificationNavigation: NotificationNavigationStore
    let onAdd: () -> Void

    @State private var people: [Person] = []
    @State private var contexts: [ReminderContext] = []
    @State private var navigationPath = NavigationPath()
    @State private var showUnavailableFromNotification = false

    private var metadata: ReminderMetadataResolver {
        ReminderMetadataResolver(personService: personService, contextService: contextService)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isEmpty {
                    emptyState
                } else if viewModel.isFilterEmpty {
                    noResultsState
                } else {
                    reminderList
                }
            }
            .background(LifeCueTheme.background.ignoresSafeArea())
            .navigationTitle("LifeCue")
            .searchable(text: $viewModel.filterState.searchText, prompt: "Search reminders")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    filterMenus
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Add reminder")
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if viewModel.filterState.isNarrowing {
                    activeFilterBar
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ReminderDetailView(
                    reminderID: id,
                    service: reminderService,
                    personService: personService,
                    contextService: contextService,
                    onChange: { viewModel.load() }
                )
            }
            .onAppear {
                reloadFilterOptions()
                installResolvers()
                viewModel.load()
                consumeNotificationNavigationIfNeeded()
            }
            .onChange(of: notificationNavigation.pendingGeneration) { _, _ in
                consumeNotificationNavigationIfNeeded()
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let warning = viewModel.corruptRecordsWarning {
                    Text(warning)
                        .font(LifeCueTheme.captionFont)
                        .foregroundStyle(LifeCueTheme.overdue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(LifeCueTheme.cardBackground)
                }
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert(
                "That reminder is no longer available.",
                isPresented: $showUnavailableFromNotification
            ) {
                Button("OK", role: .cancel) { }
            }
        }
    }

    /// Resolves a pending notification tap into ReminderDetailView (or unavailable alert).
    private func consumeNotificationNavigationIfNeeded() {
        if notificationNavigation.pendingUnavailable {
            notificationNavigation.consumeUnavailable()
            showUnavailableFromNotification = true
            return
        }
        guard let pendingID = notificationNavigation.pendingReminderID else { return }
        notificationNavigation.consumePendingOpen()

        let resolution = NotificationTapResolver.resolve(reminderID: pendingID) { id in
            try reminderService.reminder(id: id)
        }
        switch resolution {
        case .open(let id):
            // Replace path so we don't stack duplicate detail screens.
            navigationPath = NavigationPath()
            navigationPath.append(id)
            viewModel.load()
        case .unavailable:
            showUnavailableFromNotification = true
        }
    }

    // MARK: - Filter chrome

    private var filterMenus: some View {
        Menu {
            Menu {
                Button("All") { viewModel.filterState.personID = nil }
                ForEach(people) { person in
                    Button(person.name) { viewModel.filterState.personID = person.id }
                }
            } label: {
                Label(personFilterLabel, systemImage: "person")
            }

            Menu {
                Button("All") { viewModel.filterState.contextID = nil }
                ForEach(contexts) { context in
                    Button(contextFilterLabel(for: context)) {
                        viewModel.filterState.contextID = context.id
                    }
                }
            } label: {
                Label(contextFilterMenuTitle, systemImage: "folder")
            }

            Menu {
                ForEach(ReminderHomeStatusFilter.allCases) { status in
                    Button(status.title) { viewModel.filterState.status = status }
                }
            } label: {
                Label(viewModel.filterState.status.title, systemImage: "line.3.horizontal.decrease.circle")
            }

            if viewModel.filterState.isNarrowing {
                Divider()
                Button("Clear Filters") { viewModel.clearFiltersPreservingSearch() }
                Button("Clear All", role: .destructive) { viewModel.clearAllSearchAndFilters() }
            }
        } label: {
            Label(filterMenuLabel, systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel(filterMenuLabel)
    }

    private var activeFilterBar: some View {
        HStack(spacing: 8) {
            if viewModel.filterState.hasActiveFilters {
                Text(filterSummaryText)
                    .font(LifeCueTheme.captionFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)
                    .lineLimit(1)
            } else if viewModel.filterState.hasActiveSearch {
                Text("Search active")
                    .font(LifeCueTheme.captionFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)
            }
            Spacer()
            if viewModel.filterState.hasActiveFilters {
                Button("Clear Filters") {
                    viewModel.clearFiltersPreservingSearch()
                }
                .font(LifeCueTheme.captionFont)
            }
            if viewModel.filterState.isNarrowing {
                Button("Clear All") {
                    viewModel.clearAllSearchAndFilters()
                }
                .font(LifeCueTheme.captionFont)
                .foregroundStyle(LifeCueTheme.overdue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(LifeCueTheme.background.opacity(0.95))
    }

    private var filterMenuLabel: String {
        let count = viewModel.filterState.activeFilterCount
        if count == 0 { return "Filter" }
        return "Filter · \(count) active"
    }

    private var filterSummaryText: String {
        var parts: [String] = []
        if let id = viewModel.filterState.personID,
           let name = people.first(where: { $0.id == id })?.name {
            parts.append(name)
        }
        if let id = viewModel.filterState.contextID,
           let context = contexts.first(where: { $0.id == id }) {
            parts.append(contextFilterLabel(for: context))
        }
        if viewModel.filterState.status != .all {
            parts.append(viewModel.filterState.status.title)
        }
        if parts.isEmpty { return "Filters active" }
        return parts.joined(separator: " · ")
    }

    private var personFilterLabel: String {
        guard let id = viewModel.filterState.personID,
              let name = people.first(where: { $0.id == id })?.name else {
            return "Person · All"
        }
        return "Person · \(name)"
    }

    private var contextFilterMenuTitle: String {
        guard let id = viewModel.filterState.contextID,
              let context = contexts.first(where: { $0.id == id }) else {
            return "Context · All"
        }
        return "Context · \(contextFilterLabel(for: context))"
    }

    private func contextFilterLabel(for context: ReminderContext) -> String {
        if context.isGlobal { return context.name }
        if let personID = context.personID,
           let person = people.first(where: { $0.id == personID }) {
            return "\(person.name): \(context.name)"
        }
        return context.name
    }

    // MARK: - Lists

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(LifeCueTheme.today)
            Text("Nothing to remember yet")
                .font(LifeCueTheme.headlineFont)
                .foregroundStyle(LifeCueTheme.primaryText)
            Text("Capture something you don’t want to forget.")
                .font(LifeCueTheme.bodyFont)
                .foregroundStyle(LifeCueTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: onAdd) {
                Text("Add Reminder")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(LifeCueTheme.today)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("No reminders found")
                .font(LifeCueTheme.headlineFont)
                .foregroundStyle(LifeCueTheme.primaryText)
            Text("Try a different search or clear filters.")
                .font(LifeCueTheme.bodyFont)
                .foregroundStyle(LifeCueTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Clear All") {
                viewModel.clearAllSearchAndFilters()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var reminderList: some View {
        List {
            section(
                title: ReminderHomeSection.overdue.title,
                reminders: viewModel.displayedOverdue,
                tint: LifeCueTheme.overdue
            )
            section(
                title: ReminderHomeSection.today.title,
                reminders: viewModel.displayedToday,
                tint: LifeCueTheme.today
            )
            section(
                title: ReminderHomeSection.upcoming.title,
                reminders: viewModel.displayedUpcoming,
                tint: LifeCueTheme.upcoming
            )
            section(
                title: "Completed",
                reminders: viewModel.displayedCompleted,
                tint: LifeCueTheme.secondaryText
            )
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func section(title: String, reminders: [Reminder], tint: Color) -> some View {
        if !reminders.isEmpty {
            Section {
                ForEach(reminders) { reminder in
                    NavigationLink(value: reminder.id) {
                        ReminderRowView(
                            reminder: reminder,
                            accent: tint,
                            metadataLine: metadata.compactSubtitle(for: reminder)
                        )
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await viewModel.delete(reminder) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if reminder.status == .active {
                            Button {
                                Task { await viewModel.complete(reminder) }
                            } label: {
                                Label("Complete", systemImage: "checkmark")
                            }
                            .tint(LifeCueTheme.today)
                        }
                    }
                }
            } header: {
                Text(title)
                    .foregroundStyle(tint)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func reloadFilterOptions() {
        people = (try? personService.allPeople()) ?? []
        // Active contexts only for filter picker; include person-specific + global.
        let all = (try? contextService.allContexts()) ?? []
        contexts = all.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func installResolvers() {
        let resolver = metadata
        viewModel.personNameResolver = { reminder in
            resolver.personName(for: reminder)
        }
        viewModel.contextNameResolver = { reminder in
            resolver.contextName(for: reminder)
        }
    }
}

struct ReminderRowView: View {
    let reminder: Reminder
    let accent: Color
    var metadataLine: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reminder.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(LifeCueTheme.primaryText)
            Text(ReminderDisplayFormatter.subtitle(for: reminder))
                .font(LifeCueTheme.captionFont)
                .foregroundStyle(LifeCueTheme.secondaryText)
            if let metadataLine {
                Text(metadataLine)
                    .font(.footnote)
                    .foregroundStyle(LifeCueTheme.secondaryText)
                    .lineLimit(1)
            }
            if reminder.hasNote, let note = reminder.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(LifeCueTheme.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
