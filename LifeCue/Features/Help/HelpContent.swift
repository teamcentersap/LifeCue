import Foundation

struct HelpQuestion: Equatable, Identifiable, Sendable {
    let id: String
    let question: String
    let answer: String
}

struct HelpSection: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let questions: [HelpQuestion]
}

enum HelpContent {
    static let sections: [HelpSection] = [
        gettingStarted,
        creatingReminder,
        notifications,
        peopleAndContexts,
        calendar,
        imageExtraction,
        backupAndRestore,
        forwarding
    ]

    static var allQuestions: [HelpQuestion] {
        sections.flatMap(\.questions)
    }

    // MARK: - Getting Started

    private static let gettingStarted = HelpSection(
        id: "getting-started",
        title: "Getting Started",
        questions: [
            HelpQuestion(
                id: "gs-what",
                question: "What is LifeCue?",
                answer: "LifeCue helps you create and manage reminders and receive local notifications on your device."
            ),
            HelpQuestion(
                id: "gs-account",
                question: "Do I need an account?",
                answer: "No. LifeCue works locally and does not require registration or login."
            ),
            HelpQuestion(
                id: "gs-create",
                question: "How do I create a reminder?",
                answer: "Tap the + button and choose how you want to create it: Add Reminder, Photo, Camera, or Upload."
            )
        ]
    )

    // MARK: - Creating a Reminder

    private static let creatingReminder = HelpSection(
        id: "creating-reminder",
        title: "Creating a Reminder",
        questions: [
            HelpQuestion(
                id: "cr-no-time",
                question: "What happens if I don't set a time?",
                answer: "Date-only reminders use your default reminder time from Settings in the reminder's stored timezone."
            ),
            HelpQuestion(
                id: "cr-repeat",
                question: "How does Repeat work?",
                answer: "Repeat controls how often a reminder occurs. You can choose once, every day, every week, every month, or every year."
            ),
            HelpQuestion(
                id: "cr-limit-dates",
                question: "What is Limit Dates?",
                answer: "It restricts recurring reminders to an inclusive start and end date. Example: 15 Aug → 30 Aug."
            ),
            HelpQuestion(
                id: "cr-remind-me",
                question: "What is Remind me?",
                answer: "This controls when LifeCue notifies you relative to the reminder event — at the event, or before it using preset or custom offsets."
            ),
            HelpQuestion(
                id: "cr-for",
                question: "What is \"For\"?",
                answer: "It optionally associates the reminder with a Person. Example: For: Child 1. This is optional."
            ),
            HelpQuestion(
                id: "cr-context",
                question: "What is Context?",
                answer: "It optionally organizes the reminder. Examples: School, Doctor, Office, Home, Finance. Context can also be associated with a specific Person."
            ),
            HelpQuestion(
                id: "cr-calendar-prefill",
                question: "What does \"Choose upcoming event\" do?",
                answer: "It can use an upcoming calendar event to prefill reminder information such as title, date and time. It does NOT automatically create the reminder. You must still review and create the reminder."
            ),
            HelpQuestion(
                id: "cr-review",
                question: "Why should I review extracted details?",
                answer: "When creating a reminder from an image, always review the title, date, time, and note before creating the reminder."
            )
        ]
    )

    // MARK: - Notifications

    private static let notifications = HelpSection(
        id: "notifications",
        title: "Notifications",
        questions: [
            HelpQuestion(
                id: "notif-date-only",
                question: "What if I set only a date?",
                answer: "The reminder uses your default reminder time from Settings in its stored timezone."
            )
        ]
    )

    // MARK: - People & Contexts

    private static let peopleAndContexts = HelpSection(
        id: "people-contexts",
        title: "People & Contexts",
        questions: [
            HelpQuestion(
                id: "pc-no-people",
                question: "Can I use LifeCue without People?",
                answer: "Yes. People are optional."
            ),
            HelpQuestion(
                id: "pc-no-contexts",
                question: "Can I use LifeCue without Contexts?",
                answer: "Yes. Contexts are optional."
            ),
            HelpQuestion(
                id: "pc-same-context",
                question: "Can two people have the same context name?",
                answer: "Yes. Example: Child 1 → Doctor and Child 2 → Doctor. They are separate contexts."
            )
        ]
    )

    // MARK: - Calendar

    private static let calendar = HelpSection(
        id: "calendar",
        title: "Calendar",
        questions: [
            HelpQuestion(
                id: "cal-replace",
                question: "Does LifeCue replace Apple Calendar?",
                answer: "No."
            ),
            HelpQuestion(
                id: "cal-auto-create",
                question: "Does LifeCue automatically create calendar events?",
                answer: "No. Calendar events can be used to prefill reminder information."
            )
        ]
    )

    // MARK: - Image Extraction

    private static let imageExtraction = HelpSection(
        id: "image-extraction",
        title: "Image Extraction",
        questions: [
            HelpQuestion(
                id: "ie-screenshot",
                question: "Can I create a reminder from a screenshot?",
                answer: "Yes. Use Photo, Camera or Upload."
            ),
            HelpQuestion(
                id: "ie-accuracy",
                question: "Is image extraction always accurate?",
                answer: "No. Image extraction may not always identify reminder details correctly. Review the extracted details before creating the reminder."
            ),
            HelpQuestion(
                id: "ie-why",
                question: "Why can image extraction be inaccurate?",
                answer: "Images can contain multiple dates, times, names, messages, or unrelated text. LifeCue may sometimes interpret the wrong information, so always review the extracted reminder before creating it."
            )
        ]
    )

    // MARK: - Backup & Restore

    private static let backupAndRestore = HelpSection(
        id: "backup-restore",
        title: "Backup & Restore",
        questions: [
            HelpQuestion(
                id: "bk-auto",
                question: "Does LifeCue automatically back up my reminders?",
                answer: "No. Backup files are created when you choose Export Backup."
            ),
            HelpQuestion(
                id: "bk-file",
                question: "What is a .lifecuebackup file?",
                answer: "It is a portable LifeCue backup containing your reminders, People and Contexts."
            ),
            HelpQuestion(
                id: "bk-upload",
                question: "Does LifeCue upload my backup?",
                answer: "No."
            ),
            HelpQuestion(
                id: "bk-restore",
                question: "Can I restore a backup?",
                answer: "Yes. Use Backup & Restore → Import Backup."
            ),
            HelpQuestion(
                id: "bk-reminder-auto",
                question: "Does Backup Reminder create backups automatically?",
                answer: "No. You must still choose Export Backup."
            ),
            HelpQuestion(
                id: "bk-reminder-off",
                question: "Can I turn off Backup Reminder?",
                answer: "Yes. Turn off Backup Reminder in Backup & Restore."
            )
        ]
    )

    // MARK: - Forwarding

    private static let forwarding = HelpSection(
        id: "forwarding",
        title: "Forwarding",
        questions: [
            HelpQuestion(
                id: "fwd-can",
                question: "Can I forward a reminder?",
                answer: "Yes. Open the reminder and choose Forward."
            ),
            HelpQuestion(
                id: "fwd-edit",
                question: "Does editing the forwarded text change my reminder?",
                answer: "No. Forward text can be edited without changing the stored reminder."
            )
        ]
    )
}
