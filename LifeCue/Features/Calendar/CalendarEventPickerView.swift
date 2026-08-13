import SwiftUI
import UIKit

struct CalendarEventPickerView: View {
    let calendarService: CalendarServing
    let rangeFrom: Date
    let rangeTo: Date
    let onSelect: (CalendarEvent) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var vm: CalendarEventPickerViewModel

    init(
        calendarService: CalendarServing,
        rangeFrom: Date,
        rangeTo: Date,
        onSelect: @escaping (CalendarEvent) -> Void
    ) {
        self.calendarService = calendarService
        self.rangeFrom = rangeFrom
        self.rangeTo = rangeTo
        self.onSelect = onSelect
        _vm = State(initialValue: CalendarEventPickerViewModel(service: calendarService, from: rangeFrom, to: rangeTo))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Pick an event")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
        .task {
            if vm.events.isEmpty && vm.authorizationStatus == .notDetermined && vm.errorMessage == nil {
                await vm.loadInitial()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch vm.authorizationStatus {
            case .fullAccess:
                if vm.events.isEmpty {
                    Text("No events found in this time window.")
                        .foregroundStyle(LifeCueTheme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(vm.events) { event in
                            Button {
                                onSelect(event)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(LifeCueTheme.primaryText)
                                        .lineLimit(2)
                                    Text(CalendarEventDisplayFormatter.subtitle(for: event))
                                        .font(.footnote)
                                        .foregroundStyle(LifeCueTheme.secondaryText)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            case .notDetermined:
                permissionCard(
                    title: "Calendar Access",
                    message: "LifeCue can optionally use your upcoming calendar events to prefill reminder details. Your calendar stays on this device."
                ) {
                    Task { await vm.requestAccess() }
                }
            case .denied, .restricted:
                permissionDeniedCard()
            case .unavailable:
                permissionCard(
                    title: "Calendar access unavailable",
                    message: "You can continue using LifeCue without Calendar."
                ) {}
            }
        }
    }

    private func permissionCard(
        title: String,
        message: String,
        primaryAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 44))
                .foregroundStyle(LifeCueTheme.today)
            Text(title)
                .font(LifeCueTheme.headlineFont)
                .foregroundStyle(LifeCueTheme.primaryText)
                .multilineTextAlignment(.center)
            Text(message)
                .font(LifeCueTheme.bodyFont)
                .foregroundStyle(LifeCueTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
            Button("Allow Calendar Access") { primaryAction() }
                .buttonStyle(.borderedProminent)
                .tint(LifeCueTheme.today)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .background(LifeCueTheme.background.ignoresSafeArea())
    }

    private func permissionDeniedCard() -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.slash")
                .font(.system(size: 44))
                .foregroundStyle(LifeCueTheme.today)
            Text("Calendar access unavailable")
                .font(LifeCueTheme.headlineFont)
                .foregroundStyle(LifeCueTheme.primaryText)
                .multilineTextAlignment(.center)
            Text("You can continue using LifeCue without Calendar.")
                .font(LifeCueTheme.bodyFont)
                .foregroundStyle(LifeCueTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
            .tint(LifeCueTheme.today)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Button("Not Now") { dismiss() }
                .buttonStyle(.bordered)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .background(LifeCueTheme.background.ignoresSafeArea())
    }
}

@MainActor
final class CalendarEventPickerViewModel: ObservableObject {
    @Published var authorizationStatus: CalendarAuthorizationStatus = .notDetermined
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var events: [CalendarEvent] = []

    private let service: CalendarServing
    private let from: Date
    private let to: Date

    init(service: CalendarServing, from: Date, to: Date) {
        self.service = service
        self.from = from
        self.to = to
    }

    func loadInitial() async {
        isLoading = true
        defer { isLoading = false }
        authorizationStatus = await service.authorizationStatus()
        guard authorizationStatus == .fullAccess else { return }
        await loadEvents()
    }

    func requestAccess() async {
        isLoading = true
        defer { isLoading = false }
        authorizationStatus = await service.requestFullAccessToEvents()
        if authorizationStatus == .fullAccess {
            await loadEvents()
        }
    }

    private func loadEvents() async {
        do {
            events = try await service.fetchEvents(from: from, to: to, calendarIdentifiers: nil)
        } catch {
            errorMessage = "Couldn't load calendar events."
            events = []
        }
    }
}

