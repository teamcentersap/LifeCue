import SwiftUI

struct SettingsView: View {
    let notificationScheduler: NotificationScheduling

    @State private var notificationStatus: NotificationAuthorizationStatus = .notDetermined
    @State private var defaultReminderTime: Date
    @State private var appearance: LifeCueAppearance

    init(notificationScheduler: NotificationScheduling) {
        self.notificationScheduler = notificationScheduler
        let components = LifeCueSettings.defaultReminderTime
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = calendar.date(
            from: DateComponents(
                hour: components.hour ?? LifeCueSettings.fallbackDefaultHour,
                minute: components.minute ?? LifeCueSettings.fallbackDefaultMinute
            )
        ) ?? Date()
        _defaultReminderTime = State(initialValue: date)
        _appearance = State(initialValue: LifeCueSettings.appearance)
    }

    var body: some View {
        List {
            Section("Notifications") {
                LabeledContent("Notification Status", value: NotificationAuthorizationDisplay.label(for: notificationStatus))

                if NotificationAuthorizationDisplay.showsOpenSettings(for: notificationStatus) {
                    Button("Open iPhone Settings") {
                        openSystemSettings()
                    }
                }
            }

            Section {
                DatePicker(
                    "Default reminder time",
                    selection: $defaultReminderTime,
                    displayedComponents: .hourAndMinute
                )
                .onChange(of: defaultReminderTime) { _, newValue in
                    let calendar = Calendar.current
                    let components = calendar.dateComponents([.hour, .minute], from: newValue)
                    LifeCueSettings.defaultReminderTime = DateComponents(
                        hour: components.hour,
                        minute: components.minute
                    )
                }

                Text("Used for new reminders when you do not set a time. Existing reminders are not changed.")
                    .font(LifeCueTheme.captionFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)
            } header: {
                Text("Reminders")
            }

            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(LifeCueAppearance.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .onChange(of: appearance) { _, newValue in
                    LifeCueSettings.appearance = newValue
                }
            }

            Section("About") {
                NavigationLink("About LifeCue") {
                    AboutLifeCueView()
                }
            }

            Section("Privacy") {
                NavigationLink("Privacy") {
                    PrivacyView()
                }
            }
        }
        .navigationTitle("Settings")
        .task {
            await refreshNotificationStatus()
        }
        .onAppear {
            Task { await refreshNotificationStatus() }
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await notificationScheduler.authorizationStatus()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
