# LifeCue --- Codex Prompts

## Purpose

Use Codex as an independent senior engineer/architect and code reviewer.

Cursor is the primary implementation agent.

Codex should NOT blindly rewrite the project.

Use Codex to: - review architecture - inspect implementation - identify
bugs - challenge assumptions - improve tests - review Apple API usage -
perform security/privacy review - perform release review

Always provide the repository with: - `AGENTS.md` -
`LIFECUE_PRODUCT_SPEC.md` - `LIFECUE_TEST_CASES.md`

------------------------------------------------------------------------

# CODEX PROMPT 1 --- INITIAL ARCHITECTURE REVIEW

You are the senior architect reviewing the LifeCue repository before
implementation.

Read: - `AGENTS.md` - `LIFECUE_PRODUCT_SPEC.md` -
`LIFECUE_TEST_CASES.md`

Do not write application code yet.

Produce an architecture review covering:

1.  Is the V1 correctly local-first?
2.  Is a backend truly unnecessary?
3.  Is Apple Vision OCR appropriate?
4.  Is local deterministic extraction correctly separated from OCR?
5.  Is the reminder domain model sufficient?
6.  Is the rule engine testable?
7.  Are recurring/yearly/date-window reminders represented correctly?
8.  Are People and Contexts optional?
9.  Is Forward correctly separated from incoming sharing?
10. Are notifications correctly isolated behind a service?
11. Is persistence appropriate?
12. Are there unnecessary dependencies?
13. Are there App Store/privacy risks?
14. What should be changed before coding?

Do not invent requirements.

------------------------------------------------------------------------

# CODEX PROMPT 2 --- REVIEW CURSOR'S SPRINT 1

Review the current repository after Cursor completes Sprint 1.

Read all project documents.

Inspect: - SwiftUI architecture - data model - persistence -
navigation - reminder CRUD - note handling - test coverage

Find: - architecture flaws - over-engineering - under-engineering -
state-management problems - persistence problems - accessibility
issues - likely future migration problems

Do not rewrite everything.

Return: 1. Critical issues 2. Important issues 3. Minor issues 4.
Recommended changes 5. Tests missing

Only make code changes if explicitly instructed.

------------------------------------------------------------------------

# CODEX PROMPT 3 --- REVIEW SPRINT 2 REMINDER ENGINE

Review notification and reminder scheduling.

Read: - product spec - tests - current implementation

Check: - local notification architecture - cancellation - rescheduling -
duplicate notifications - stale notifications - timezone handling - date
calculations - testability - completion behavior - snooze behavior

Pay special attention to: - month/year boundaries - recurrence -
daylight saving where applicable

Identify deterministic bugs.

If you modify code, keep changes minimal and run tests.

------------------------------------------------------------------------

# CODEX PROMPT 4 --- REVIEW OCR + LOCAL EXTRACTION

Review Sprint 3 and Sprint 4.

Verify: - correct Vision OCR API usage - no cloud AI - no backend - no
hidden network dependency - OCR errors handled - parser separated from
OCR - parser does not invent data - ambiguous dates are exposed to
user - extraction is unit-testable - poor OCR has a manual fallback

Challenge the extraction strategy.

Do not recommend adding AI unless explicitly asked.

------------------------------------------------------------------------

# CODEX PROMPT 5 --- REVIEW AI-FREE CONFIRMATION FLOW

Review Sprint 5.

Verify this exact invariant:

``` text
Image
→ OCR
→ Local extraction
→ Draft
→ Review
→ User confirmation
→ Active reminder
```

Prove that: - no notification is scheduled for a draft - cancellation
creates no reminder - edits are preserved - missing fields remain
missing - no parser output silently becomes an active reminder

Find any path that violates the invariant.

------------------------------------------------------------------------

# CODEX PROMPT 6 --- REVIEW ADVANCED REMINDER RULES

Review Sprint 6.

Test: - yearly - monthly - weekly - multiple offsets - date windows -
start/end dates - stop conditions - completion - duplicate occurrences -
leap years - month lengths - timezone

Look for: - off-by-one errors - duplicate notifications - invalid
dates - infinite recurrence - stale scheduled notifications

Add tests where needed.

------------------------------------------------------------------------

# CODEX PROMPT 7 --- REVIEW PEOPLE, CONTEXTS, CALENDAR

Review Sprint 7.

Verify: - People are optional - Contexts are optional - same context
name can exist for different people - deleting/unlinking person does not
corrupt reminder - deleting/unlinking context does not corrupt
reminder - Calendar reflects actual reminder dates - Calendar does not
become a second reminder engine

Challenge unnecessary complexity.

------------------------------------------------------------------------

# CODEX PROMPT 8 --- REVIEW FORWARD

Review Sprint 8.

Verify:

``` text
Reminder
→ deterministic formatter
→ editable text
→ native iOS sharing
```

Confirm: - no AI - no network - no WhatsApp API - no Gmail API - no
automatic sending - no incoming Share Extension

Check message formatting for: - title only - title + date - title +
date + time - person - note - missing fields

Verify the product requirement is satisfied without over-engineering.

------------------------------------------------------------------------

# CODEX PROMPT 9 --- FULL SECURITY + PRIVACY REVIEW

Perform a release-oriented review.

Check: - no secrets - no cloud AI - no backend - no sensitive logging -
no unnecessary analytics SDKs - no unexpected network traffic -
permission timing - local data handling - source image retention - data
isolation - unsafe URL handling - file handling - crashes

Identify anything that could create App Store review/privacy concerns.

Do not claim approval is guaranteed.

------------------------------------------------------------------------

# CODEX PROMPT 10 --- FULL RELEASE REVIEW

This is the final review before TestFlight.

Read all project documents.

Run the full test suite.

Check: - build configuration - warnings - crashes - accessibility -
Dynamic Type - dark mode if supported - small/large devices - offline
behavior - notification behavior - date/time - OCR - extraction -
confirmation - People - Context - Calendar - Forward

Verify the final product still matches the product specification.

Produce:

## Release blockers

## High-risk issues

## Medium-risk issues

## Low-risk issues

## Tests passed

## Tests failed

## Known limitations

## Recommended actions before TestFlight

Do not add new features.
