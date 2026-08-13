# LifeCue --- Cursor Prompts

## How to use

Put these files in the repository root:

-   `AGENTS.md`
-   `LIFECUE_PRODUCT_SPEC.md`
-   `LIFECUE_TEST_CASES.md`

Use the Master Prompt first. It must produce an architecture plan and
MUST NOT code yet.

Then run Sprint 1 through Sprint 9 sequentially.

------------------------------------------------------------------------

# MASTER PROMPT --- FIRST CURSOR PROMPT

You are the lead iOS architect and senior software engineer for LifeCue.

Before writing code, read completely: - `AGENTS.md` -
`LIFECUE_PRODUCT_SPEC.md` - `LIFECUE_TEST_CASES.md`

Treat them as the current product and engineering contract.

## DO NOT CODE YET.

First analyze the requirements and produce an implementation plan.

Your response must include:

### 1. Product understanding

Summarize: - core user problem - core user journey - V1 scope - explicit
exclusions

### 2. iOS architecture

Propose: - SwiftUI architecture - navigation - state management - local
persistence - reminder domain model - rule engine - notification
service - OCR service - local extraction architecture - Forward
architecture

### 3. Backend decision

Confirm that V1 does NOT require a backend because: - OCR is on-device -
extraction is local - reminders are local - notifications are local -
Forward is local/system sharing

Do not introduce a backend unless a requirement proves it necessary.

### 4. Data model

Propose the minimum models for: - Reminder - ReminderRule -
ReminderOccurrence if needed - Person - Context - Source - local
settings

Explain optional relationships.

### 5. OCR/extraction architecture

Use Apple Vision OCR.

Explain how recognized text will be converted into candidate fields
using deterministic local parsing.

Include: - date parser - time parser - recurrence parser - title/action
extraction - optional person extraction - note/details extraction -
ambiguity handling

### 6. Extraction failure

Define how the UI behaves when: - all information is extracted - partial
information is extracted - OCR is poor - no useful text exists

### 7. Reminder engine

Explain: - before-event offsets - multiple reminders - yearly
recurrence - date windows - stop conditions - snooze - reschedule -
timezone handling

### 8. Forward

Confirm: - no AI - deterministic text - editable preview - native iOS
system sharing - no incoming Share Extension - no WhatsApp/Gmail APIs

### 9. Testing

Map modules to tests from `LIFECUE_TEST_CASES.md`.

### 10. Repository structure

Propose a maintainable SwiftUI project structure.

### 11. Risks

List: - Apple API assumptions to verify - date/time risks - OCR
limitations - App Store considerations - persistence risks -
notification limits

### 12. Sprint mapping

Map the architecture to Sprint 1--9 below.

Do not create code.

Do not add features.

Wait for the next instruction.

------------------------------------------------------------------------

# SPRINT 1 --- FOUNDATION

Implement Sprint 1 only.

Read all three project documents first.

Build: - Xcode project foundation - SwiftUI navigation - theme - Home -
empty state - manual Add Reminder - Reminder model - local persistence -
reminder list - detail screen - edit - delete - complete - note - basic
domain tests

Do NOT build: - OCR - extraction - AI - backend - notifications -
Calendar - People UI - Context UI - Forward

Run tests and report: - files changed - tests - failures - architecture
concerns

------------------------------------------------------------------------

# SPRINT 2 --- NOTIFICATIONS + RULE ENGINE

Implement Sprint 2 only.

Build: - notification permission flow - local notification service -
exact date/time reminders - before-event reminders - multiple reminder
offsets - snooze - reschedule - completion cancellation - deletion
cancellation - update/reschedule behavior - rule calculation layer

Test: - 1 day before - 1 week before - multiple reminders - month
boundary - year boundary - timezone

Use official Apple notification APIs.

Do not add advanced recurrence/date-window functionality beyond what is
needed for a sound foundation.

------------------------------------------------------------------------

# SPRINT 3 --- IMAGE CAPTURE + OCR

Implement Sprint 3 only.

Build: - Upload Image using native Photos Picker - Take Photo - image
preview - processing state - Vision OCR - OCR error handling -
permission handling - no-text handling

Critical: - Do NOT add Share Extension. - Do NOT make LifeCue an
incoming Share Sheet destination. - Do NOT add cloud AI. - Do NOT add
backend.

Prefer on-device OCR.

Add OCR tests using representative fixtures where practical.

------------------------------------------------------------------------

# SPRINT 4 --- LOCAL SMART EXTRACTION

Implement Sprint 4 only.

There is NO AI and NO backend.

Build a deterministic local extraction layer on top of Vision OCR.

Support, where reliably detectable: - title/action - date - time -
deadline/expiration - recurrence phrases - optional person - useful
note/details

Use native Apple capabilities and conservative deterministic parsing.

Important: - never invent information - return nil/unknown when
uncertain - preserve ambiguity for user review

Build: - extraction service/protocol - date parser - time parser -
recurrence parser - candidate title/action logic - candidate note
logic - confidence/ambiguity state where useful

Add extensive unit tests.

------------------------------------------------------------------------

# SPRINT 5 --- REVIEW + CONFIRMATION + FAILURE UX

Implement Sprint 5 only.

Connect:

Image → OCR → Local extraction → Draft → Review → Edit → Confirm →
Active Reminder

Build Review screen with: - title - date - time - person - context if
available - note - reminder schedule

Rules: - every important field editable - optional fields can be empty -
user explicitly presses Create Reminder - no notification before
confirmation - user edits are preserved - no silent assumptions

Failure states: 1. partial extraction 2. poor OCR 3. no useful text 4.
no date 5. ambiguous date

Show whatever was extracted.

Allow: - Try Another Image - Add Reminder Manually

Never invent missing information.

------------------------------------------------------------------------

# SPRINT 6 --- ADVANCED REMINDER RULES

Implement Sprint 6 only.

Add: - yearly recurrence - monthly recurrence - weekly recurrence where
specified - custom recurrence where practical - date windows - start
date - end date - time-of-day - multiple rules - stop after completion -
stop after end date - enable/disable rule

Examples: - annual reminder - every 2 days between two dates - multiple
reminders before an event

Add extensive unit tests.

Do not clutter the basic UI. Advanced scheduling belongs behind the
scheduling/custom screen.

------------------------------------------------------------------------

# SPRINT 7 --- PEOPLE + CONTEXTS + CALENDAR

Implement Sprint 7 only.

People: - list - add - edit - optional reminder link

Contexts: - create - edit - optional reminder link - person-specific
contexts

Must support:

Sanchit → Health Saachi → Health

These are separate.

A reminder must still work with no People/Context.

Calendar: - month view - reminder indicators - selected date - reminder
list - open detail

Do not build full calendar management.

------------------------------------------------------------------------

# SPRINT 8 --- FORWARD

Implement Sprint 8 only.

Feature name: Forward.

Flow:

Reminder → Forward → deterministic text → editable preview → iOS system
sharing

Text fields: - title - person if present - date - time - note

Do NOT: - use AI - use network - call WhatsApp - call Gmail -
auto-send - select recipient - add Share Extension

Add tests for missing fields and edited outgoing text.

Verify that LifeCue is not registered as an incoming Share Sheet
destination.

------------------------------------------------------------------------

# SPRINT 9 --- HARDENING + RELEASE

Implement Sprint 9 only.

Do not add features.

Review: - architecture - persistence - concurrency - memory - UI state -
notifications - date/time - OCR - extraction - privacy - accessibility -
error handling - performance

Run every test in `LIFECUE_TEST_CASES.md`.

Verify: - no cloud AI - no backend dependency - no incoming Share
Extension - no WhatsApp/Gmail APIs - no secrets - no sensitive logs

Test on real iOS devices.

Prepare TestFlight/release configuration.

Report: - tests passed - tests failed - warnings - release blockers -
known limitations - exact build/test commands
