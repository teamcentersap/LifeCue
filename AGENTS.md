# AGENTS.md --- LifeCue Engineering Contract

## Read First

Before modifying code, read: 1. `AGENTS.md` 2. `LIFECUE_PRODUCT_SPEC.md`
3. `LIFECUE_TEST_CASES.md`

These documents are the product and engineering contract.

------------------------------------------------------------------------

# 1. Mission

Build LifeCue as a simple, reliable iOS reminder application.

Core promise:

> Capture something you do not want to forget. Review it. LifeCue
> remembers it for you.

Do not turn LifeCue into a general productivity platform.

------------------------------------------------------------------------

# 2. Non-Negotiable Decisions

## 2.1 No Paid/Cloud AI in V1

V1 MUST NOT use: - OpenAI API - Anthropic API - Gemini API - cloud LLM
APIs - paid OCR APIs

Screenshot extraction uses: - Apple Vision OCR - local deterministic
parsing - native Apple capabilities where appropriate

If information cannot be reliably extracted: - show what was extracted -
tell the user that some information could not be identified - allow
manual correction - never invent missing data

------------------------------------------------------------------------

## 2.2 No Backend in V1

Do not create a backend, API server, PostgreSQL database, cloud
database, or authentication service for V1.

V1 is local-first.

Use the backend only in a future sprint/product decision if the scope
changes.

------------------------------------------------------------------------

## 2.3 No Incoming Share Extension

LifeCue MUST NOT appear in the iOS incoming Share Sheet in V1.

Do not implement: - Share Extension - app extension for incoming
images - WhatsApp → LifeCue - Gmail → LifeCue - Photos → LifeCue

The user must open LifeCue and choose Upload Image/Take Photo.

------------------------------------------------------------------------

## 2.4 Forward Is Outgoing Only

Forward: - is initiated inside LifeCue - generates text
deterministically - is editable - uses the native iOS sharing mechanism

Do not: - call AI - call WhatsApp APIs - call Gmail APIs - auto-send -
auto-select recipients

------------------------------------------------------------------------

## 2.5 AI/Extraction Draft Safety

Image extraction creates a draft only.

Never schedule a notification before the user explicitly confirms.

Never invent: - dates - times - people - recurrence - medical facts

------------------------------------------------------------------------

# 3. iOS Technology Rules

Use: - Swift - SwiftUI - Apple-native APIs - Vision - PhotosUI/Photos
Picker - camera APIs - UserNotifications - native sharing APIs -
Apple-native persistence appropriate to the supported deployment target

Do not add cross-platform frameworks.

Do not add third-party dependencies when native APIs are sufficient.

Before using an uncertain Apple API, verify official Apple
documentation. Never invent an API.

------------------------------------------------------------------------

# 4. Local-First Architecture

V1 should conceptually be:

``` text
SwiftUI
  ↓
Presentation
  ↓
Domain / Use Cases
  ↓
Persistence
  ↓
Reminder Rule Engine
  ↓
UserNotifications
```

Capture:

``` text
Photos/Camera
  ↓
Vision OCR
  ↓
Local Extraction
  ↓
Draft
  ↓
Review
  ↓
Confirmed Reminder
```

Forward:

``` text
Reminder
  ↓
Deterministic Formatter
  ↓
Editable Text
  ↓
iOS System Share
```

------------------------------------------------------------------------

# 5. Architecture Principles

-   Separate UI, domain logic, persistence, OCR, extraction, and
    notification scheduling.
-   Reminder rule calculations must be independently testable.
-   Avoid massive view files.
-   Avoid business logic inside SwiftUI views.
-   Avoid global mutable state.
-   Prefer dependency injection for services.
-   Keep extraction parser replaceable.
-   Keep notification scheduling behind a service abstraction.
-   Keep persistence behind a repository/data layer where appropriate.
-   Avoid premature abstractions.

------------------------------------------------------------------------

# 6. UI Rules

The user should be able to:

``` text
Open
→ +
→ Capture/Add
→ Review
→ Create
```

Do not force: - People - Contexts - categories - family setup

The UI must be: - modern - minimal - readable - calm - accessible -
iOS-native

Do not copy another app's UI.

------------------------------------------------------------------------

# 7. People/Context Rules

People are optional.

Contexts are optional.

The same context name can exist for different people:

``` text
Sanchit → Health
Saachi → Health
```

These must remain separate.

Do not force a context during reminder creation.

------------------------------------------------------------------------

# 8. Date/Time Rules

Use typed date/time representations.

Never use ambiguous display strings as the internal source of truth.

Test: - month boundaries - year boundaries - leap years - recurrence -
timezone - DST where applicable

------------------------------------------------------------------------

# 9. Notifications

Use local UserNotifications.

The rule engine calculates occurrences.

Never scatter notification scheduling throughout UI code.

Editing/deleting/completing a reminder must correctly update/cancel
scheduled notifications.

------------------------------------------------------------------------

# 10. OCR/Extraction Rules

Use on-device Apple Vision OCR.

The local extraction layer should be: - deterministic - testable -
conservative

When uncertain: - return nil/unknown - do not guess

Extraction should be separated into small parsers where practical: -
dates - times - recurrence - action/title - person - notes

Do not create a pseudo-LLM with hundreds of opaque heuristics.

------------------------------------------------------------------------

# 11. Privacy

Do not log: - full screenshots - complete OCR text - reminder notes -
sensitive extracted content

in release builds.

Do not upload images.

Do not add analytics SDKs unless explicitly requested.

Request permissions only when necessary.

------------------------------------------------------------------------

# 12. Testing

Every non-trivial module requires tests.

P0 tests: - manual reminder CRUD - persistence - notifications - rule
calculations - yearly recurrence - date windows - OCR - extraction -
extraction failure - confirmation safety - People optionality - Context
optionality - Forward - no incoming Share Extension

Run tests before declaring a sprint complete.

------------------------------------------------------------------------

# 13. No Feature Creep

Do not implement features not requested by the current sprint.

Examples requiring explicit approval: - backend - cloud sync -
accounts - subscriptions - AI - Share Extension - Gmail - WhatsApp -
Siri - family collaboration - location reminders - external monitoring

------------------------------------------------------------------------

# 14. Agent Workflow

For each sprint:

1.  Read relevant requirements.
2.  Inspect current repository.
3.  Explain planned changes briefly.
4.  Implement only the sprint.
5.  Run relevant tests.
6.  Run regression tests.
7.  Review for security/privacy.
8.  Report files changed.
9.  Report tests run and results.
10. Report remaining issues.

Do not silently ignore test failures.

------------------------------------------------------------------------

# 15. If Requirements Conflict

Stop and explain: - the conflict - affected modules - safest
interpretation

Do not silently invent a product decision.

------------------------------------------------------------------------

# 16. Definition of Done

A sprint is done only when: - implementation works - relevant tests
pass - errors are handled - no forbidden feature is introduced - code is
maintainable - existing behavior is not unnecessarily broken -
documentation is updated if architecture changes
