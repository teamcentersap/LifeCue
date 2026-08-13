import SwiftUI
import UIKit

struct CalendarUpcomingView: View {
    let calendarService: CalendarServing

    @StateObject private var vm: CalendarUpcomingViewModel

    init(calendarService: CalendarServing) {
        self.calendarService = calendarService
        _vm = StateObject(wrappedValue: CalendarUpcomingViewModel(service: calendarService))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Calendar")
        }
        .task {
            if vm.events.isEmpty && vm.errorMessage == nil {
                await vm.loadInitial()
            } else {
                // Still refresh authorization if not yet loaded.
                if vm.authorizationStatus == .notDetermined {
                    await vm.loadInitial()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.authorizationStatus != .fullAccess {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch vm.authorizationStatus {
            case .fullAccess:
                eventsList
            case .notDetermined:
                permissionCard(
                    title: "Calendar Access",
                    message: "LifeCue can optionally show your upcoming calendar events while you create reminders. Your calendar stays on this device."
                ) {
                    Task { await vm.requestAccess() }
                }
            case .denied, .restricted:
                permissionDeniedCard(
                    status: vm.authorizationStatus
                )
            case .unavailable:
                permissionCard(
                    title: "Calendar access unavailable",
                    message: "You can continue using LifeCue without Calendar."
                ) {}
            }
        }
    }

    private var eventsList: some View {
        Group {
            if let errorMessage = vm.errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .foregroundStyle(LifeCueTheme.secondaryText)
                    Button("Try Again") {
                        Task { await vm.loadInitial() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.events.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "calendar")
                        .font(.system(size: 48))
                        .foregroundStyle(LifeCueTheme.secondaryText)
                    Text("No upcoming events")
                        .font(LifeCueTheme.headlineFont)
                        .foregroundStyle(LifeCueTheme.primaryText)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(vm.events) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(LifeCueTheme.primaryText)
                                .lineLimit(2)
                            Text(event.calendarName)
                                .font(.footnote)
                                .foregroundStyle(LifeCueTheme.secondaryText)
                            Text(CalendarEventDisplayFormatter.subtitle(for: event))
                                .font(.footnote)
                                .foregroundStyle(LifeCueTheme.secondaryText)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
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
            Button("Allow Calendar Access") {
                primaryAction()
            }
            .buttonStyle(.borderedProminent)
            .tint(LifeCueTheme.today)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(LifeCueTheme.background.ignoresSafeArea())
    }

    private func permissionDeniedCard(status: CalendarAuthorizationStatus) -> some View {
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

            Button("Not Now") { vm.errorMessage = nil }
                .buttonStyle(.bordered)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .background(LifeCueTheme.background.ignoresSafeArea())
    }
}

