# LifeCue --- Test Cases & Acceptance Criteria

## 1. Test Strategy

Test levels: 1. Unit tests 2. Domain/service tests 3. UI tests 4.
Integration tests 5. Notification tests 6. OCR/extraction tests 7.
Regression tests 8. Device/manual acceptance tests

Critical principle:

> Image extraction creates a draft only. No reminder becomes active
> until the user confirms it.

------------------------------------------------------------------------

# 2. Home

## TC-HOME-001 --- Empty state

Priority: P0

Steps: 1. Launch with no reminders. 2. Open Home.

Expected: - Empty state appears. - `+` is visible. - No fake data
appears.

## TC-HOME-002 --- Today

Priority: P0

Create a reminder for today.

Expected: - Appears under Today. - Correct date/time shown.

## TC-HOME-003 --- Upcoming

Priority: P0

Create a future reminder.

Expected: - Appears under Upcoming.

## TC-HOME-004 --- Overdue

Priority: P0

Create a past-due reminder.

Expected: - Clearly marked overdue. - Not silently deleted.

------------------------------------------------------------------------

# 3. Manual Reminder

## TC-REM-001 --- Create

Priority: P0

Create title + date/time.

Expected: - Reminder saved locally. - Appears on Home.

## TC-REM-002 --- Create without Person/Context

Priority: P0

Expected: - Reminder can be created.

## TC-REM-003 --- Note

Priority: P0

Add/edit note.

Expected: - Exact note is retained.

## TC-REM-004 --- Edit

Priority: P0

Edit title/date/time/note.

Expected: - Changes persist. - Notification schedule updates as needed.

## TC-REM-005 --- Delete

Priority: P0

Delete reminder.

Expected: - Reminder removed. - Notifications cancelled.

## TC-REM-006 --- Complete

Priority: P0

Complete reminder.

Expected: - Status becomes completed. - Future notifications stop.

## TC-REM-007 --- Persistence

Priority: P0

Restart app.

Expected: - Reminder remains.

------------------------------------------------------------------------

# 4. Image Capture

## TC-CAP-001 --- Photos Picker

Priority: P0

Tap `+` → Upload Image.

Expected: - Native Photos Picker opens. - Selected image is shown.

## TC-CAP-002 --- Cancel picker

Priority: P1

Expected: - Returns to app. - No reminder created.

## TC-CAP-003 --- Camera

Priority: P1

Tap Take Photo and capture image.

Expected: - Image preview appears.

## TC-CAP-004 --- Camera denied

Priority: P1

Expected: - No crash. - Clear recovery path.

## TC-CAP-005 --- No incoming Share Extension

Priority: P0

Verify app configuration.

Expected: - LifeCue is NOT registered as an incoming Share Sheet
destination.

------------------------------------------------------------------------

# 5. OCR

## TC-OCR-001 --- Clear text

Priority: P0

Use a clear screenshot containing title/date/time.

Expected: - Apple Vision recognizes the text.

## TC-OCR-002 --- Poor image

Priority: P1

Use blurry/low-quality image.

Expected: - App handles partial OCR. - No crash. - User can retry/manual
entry.

## TC-OCR-003 --- No text

Priority: P1

Use image with no useful text.

Expected: - No fake reminder. - Manual reminder option shown.

## TC-OCR-004 --- Large image

Priority: P1

Use a large/high-resolution image.

Expected: - App remains stable. - Loading/progress state is shown if
needed.

------------------------------------------------------------------------

# 6. Local Extraction

## TC-EXT-001 --- Simple date

Input: `Science project is due on 25 August.`

Expected: - Date extracted as 25 August. - Draft created.

## TC-EXT-002 --- Date and time

Input: `Doctor appointment on 18 September at 4 PM.`

Expected: - Date and time extracted.

## TC-EXT-003 --- Person

Input: `Sanchit's appointment is on 18 September.`

Expected: - Sanchit may be proposed if reliably identified. - Must be
editable.

## TC-EXT-004 --- Note

Input: `Bring previous reports and ask about test results.`

Expected: - Supporting text can become note/details.

## TC-EXT-005 --- Yearly

Input: `Annual medical test every year.`

Expected: - Yearly recurrence can be proposed only when reliably
understood. - User reviews before creation.

## TC-EXT-006 --- Missing date

Input: `Remember to call Rahul.`

Expected: - Action/title extracted. - Date remains unset. - No date
invented.

## TC-EXT-007 --- Ambiguous date

Input: `05/09/26`

Expected: - Locale/device rules are applied. - User sees the result and
can correct it.

## TC-EXT-008 --- Multiple dates

Input: `Registration 10 Aug. Last date 20 Aug. Event 25 Aug.`

Expected: - Candidate information is presented. - No hidden
assumption. - User can correct.

------------------------------------------------------------------------

# 7. Extraction Failure UX

## TC-FAIL-001 --- Partial extraction

Priority: P0

Expected: - Show whatever was extracted. - Clearly indicate that some
information could not be identified. - User can manually fill missing
fields.

## TC-FAIL-002 --- OCR insufficient

Priority: P0

Expected: - Explain that image could not be read sufficiently. - Offer
Try Another Image. - Offer Add Reminder Manually.

## TC-FAIL-003 --- No reminder structure

Priority: P1

Expected: - Do not invent title/date/time. - Show useful recognized text
where practical. - Allow manual reminder creation.

## TC-FAIL-004 --- No cloud AI

Priority: P0

Verify network/backend configuration.

Expected: - Image extraction does not require a paid/cloud AI API.

------------------------------------------------------------------------

# 8. Confirmation Safety

## TC-CONF-001 --- No automatic scheduling

Priority: P0 / critical

Steps: 1. Upload image. 2. OCR/extraction completes. 3. Do not press
Create Reminder.

Expected: - No active reminder notification exists.

## TC-CONF-002 --- User edits extracted data

Priority: P0

Change title/date/time/note.

Expected: - Final values are used.

## TC-CONF-003 --- Cancel draft

Priority: P0

Expected: - No active reminder created.

## TC-CONF-004 --- Confirm

Priority: P0

Expected: - Reminder is persisted. - Notification follows confirmed
schedule.

------------------------------------------------------------------------

# 9. Reminder Rules

## TC-RULE-001 --- One day before

Event: 25 Aug

Expected: - Occurrence = 24 Aug at configured time.

## TC-RULE-002 --- One week before

Expected: - Occurrence = 18 Aug.

## TC-RULE-003 --- Multiple reminders

Event: 30 Sep

Rules: - 30 days - 7 days - 1 day

Expected: - All three occurrences.

## TC-RULE-004 --- Yearly

Event: 30 Sep 2026

Expected: - Next yearly occurrence = 30 Sep 2027.

## TC-RULE-005 --- Monthly

Expected: - Correct monthly recurrence.

## TC-RULE-006 --- Date window

Start: 1 Sep End: 15 Sep Every: 2 days

Expected: - Only dates inside window are generated.

## TC-RULE-007 --- Completion stop

Expected: - Future occurrences stop after completion when configured.

## TC-RULE-008 --- End date stop

Expected: - No occurrence after end date.

## TC-RULE-009 --- Disabled rule

Expected: - No notification for disabled rule.

------------------------------------------------------------------------

# 10. Date/Time Edge Cases

## TC-DATE-001 --- Month boundary

31 Aug → 1 Sep

Expected: - Correct occurrence.

## TC-DATE-002 --- Year boundary

31 Dec → 1 Jan

Expected: - Correct occurrence.

## TC-DATE-003 --- Leap year

Expected: - No invalid dates.

## TC-DATE-004 --- Timezone

Expected: - Correct local notification time.

## TC-DATE-005 --- DST where applicable

Expected: - No duplicate/invalid occurrence.

------------------------------------------------------------------------

# 11. Notifications

## TC-NOTIF-001 --- Permission granted

Expected: - Notification appears.

## TC-NOTIF-002 --- Permission denied

Expected: - App continues working. - User can recover through settings.

## TC-NOTIF-003 --- Edit reminder

Expected: - Old notification removed/replaced.

## TC-NOTIF-004 --- Delete reminder

Expected: - Notification cancelled.

## TC-NOTIF-005 --- Complete

Expected: - Future notification cancelled.

## TC-NOTIF-006 --- Recurrence

Expected: - Next occurrence remains correct.

------------------------------------------------------------------------

# 12. People

## TC-PEOPLE-001 --- No people

Expected: - App works normally.

## TC-PEOPLE-002 --- Add person

Expected: - Person created.

## TC-PEOPLE-003 --- Link reminder

Expected: - Person displayed on reminder.

## TC-PEOPLE-004 --- Remove link

Expected: - Reminder remains valid.

------------------------------------------------------------------------

# 13. Contexts

## TC-CONTEXT-001 --- No context

Expected: - Reminder can be created.

## TC-CONTEXT-002 --- Create context

Expected: - Context available for future use.

## TC-CONTEXT-003 --- Sanchit Health

Expected: - Sanchit has independent Health context.

## TC-CONTEXT-004 --- Saachi Health

Expected: - Saachi can also have Health. - It remains separate from
Sanchit's Health.

## TC-CONTEXT-005 --- Optional

Expected: - Context can be ignored entirely.

------------------------------------------------------------------------

# 14. Calendar

## TC-CAL-001 --- Month view

Expected: - Correct month and dates.

## TC-CAL-002 --- Reminder indicator

Expected: - Reminder appears on correct date.

## TC-CAL-003 --- Date selection

Expected: - Selected date's reminders appear.

## TC-CAL-004 --- Open reminder

Expected: - Detail screen opens.

------------------------------------------------------------------------

# 15. Forward

## TC-FWD-001 --- Basic message

Reminder: Doctor Appointment Sanchit 18 Sep 4 PM Take reports.

Expected: - Correct deterministic text.

## TC-FWD-002 --- Missing person

Expected: - No empty person line.

## TC-FWD-003 --- Missing time

Expected: - No fake time.

## TC-FWD-004 --- Missing note

Expected: - No empty note section.

## TC-FWD-005 --- Edit outgoing text

Expected: - User can modify text.

## TC-FWD-006 --- iOS sharing

Expected: - Native iOS system sharing opens.

## TC-FWD-007 --- No AI

Expected: - Forward never invokes AI or network extraction.

## TC-FWD-008 --- No direct integrations

Expected: - No WhatsApp API. - No Gmail API.

------------------------------------------------------------------------

# 16. Source Image

## TC-SRC-001 --- Source available

Expected: - Reminder can show source image reference.

## TC-SRC-002 --- View original

Expected: - Original opens when retained.

## TC-SRC-003 --- Delete source

Expected: - Reminder remains valid.

------------------------------------------------------------------------

# 17. Privacy/Security

## TC-PRIV-001 --- No sensitive production logs

Expected: - No full screenshots/OCR text in release logs.

## TC-PRIV-002 --- No AI keys

Expected: - No AI provider keys exist because V1 uses no cloud AI.

## TC-PRIV-003 --- Permission timing

Expected: - Permissions requested only when needed.

## TC-PRIV-004 --- No external app monitoring

Expected: - App does not read WhatsApp/Gmail/other apps.

------------------------------------------------------------------------

# 18. Offline Behavior

## TC-OFF-001 --- Create reminder offline

Expected: - Manual reminder works.

## TC-OFF-002 --- Notifications offline

Expected: - Scheduled local notification works without server access.

## TC-OFF-003 --- Forward offline

Expected: - Deterministic text generation and system sharing work
without a LifeCue backend.

------------------------------------------------------------------------

# 19. Error Handling

## TC-ERR-001 --- OCR error

Expected: - Clear error/retry/manual flow.

## TC-ERR-002 --- Parser error

Expected: - App does not crash. - User can manually edit/create.

## TC-ERR-003 --- Invalid date

Expected: - User is asked to correct it.

## TC-ERR-004 --- Notification scheduling failure

Expected: - User receives useful feedback. - Reminder data remains
intact.

------------------------------------------------------------------------

# 20. Release Acceptance

Before TestFlight: - Release build succeeds. - No debug secrets. - No
paid AI service. - No backend dependency for V1. - No incoming Share
Extension. - Permissions are accurate. - Privacy disclosures are
accurate. - Critical tests pass. - Real-device smoke testing
completed. - Accessibility basics completed. - No major crashes. - No
silent AI-like guessing.

------------------------------------------------------------------------

# 21. P0 Acceptance Criteria

1.  Manual reminder creation works.
2.  Reminder persists locally.
3.  Notifications work.
4.  Image selection works.
5.  Camera works.
6.  Vision OCR works.
7.  Local extraction never invents information.
8.  Partial extraction is shown to the user.
9.  Extraction failure has a manual fallback.
10. User must confirm before activation.
11. Notes work.
12. Multiple reminders work.
13. Yearly reminders work.
14. Date-window reminders work.
15. People are optional.
16. Contexts are optional.
17. Person-specific contexts remain separate.
18. Calendar works.
19. Forward works without AI.
20. LifeCue is not an incoming Share Sheet destination.
21. V1 has no cloud AI dependency.
22. V1 has no backend dependency.
