# LifeCue --- Product Specification & Implementation Blueprint

**Status:** V1 master specification\
**Platform:** iOS first\
**Android:** Later phase\
**Working name:** LifeCue --- verify App Store, trademark, and domain
availability before launch.

------------------------------------------------------------------------

# 1. Product Vision

LifeCue is a simple reminder application for real-life information.

### Core promise

> **Capture something you do not want to forget. Review it. LifeCue
> remembers it for you.**

LifeCue is intended for: - individuals - parents - students/children -
employees - freelancers - families - anyone who receives information
containing dates, deadlines, appointments, tasks, renewals, or
follow-ups.

The product must remain extremely simple for normal users while
supporting optional organization for users who want more structure.

## Product philosophy

-   Real-world information first.
-   A reminder should take seconds to create.
-   Organization is optional.
-   Context is optional.
-   People are optional.
-   AI is NOT required for V1.
-   Screenshot/image extraction must use free, on-device Apple
    capabilities.
-   Never invent information.
-   User always reviews extracted information before an active reminder
    is created.
-   Forward is deterministic and does not use AI.
-   Do not turn the product into a general productivity platform.

------------------------------------------------------------------------

# 2. V1 Product Boundary

## Included

-   Manual reminder creation
-   Notes
-   Image upload from inside the app
-   Take photo from inside the app
-   Apple Vision OCR
-   Local/deterministic information extraction
-   Review/edit extracted information
-   Reminder scheduling
-   Multiple reminder offsets
-   Recurring reminders
-   Yearly reminders
-   Date-window reminders
-   Snooze
-   Complete
-   Reschedule
-   Optional People
-   Optional Contexts
-   Person-specific contexts
-   Lightweight Calendar
-   Forward reminder text using the iOS system sharing mechanism
-   Local persistence
-   Local notifications

## Explicitly excluded from V1

-   Paid/cloud AI APIs
-   AI backend
-   AI-generated Forward messages
-   iOS incoming Share Extension
-   LifeCue appearing in another app's Share Sheet as an incoming
    destination
-   Automatic WhatsApp reading
-   Automatic Gmail reading
-   Reading other apps
-   Background monitoring of other apps
-   WhatsApp API integration
-   Gmail API integration
-   Automatic message sending
-   Automatic recipient selection
-   Full family collaboration/permissions
-   Full medical record management
-   Full calendar replacement
-   Location-triggered reminders
-   Conditional external monitoring
-   Social/community features
-   Complex subscription infrastructure unless required for launch

------------------------------------------------------------------------

# 3. Core User Mental Model

The primary behavior is:

``` text
OPEN LIFE CUE
    ↓
PRESS +
    ↓
CAPTURE SOMETHING
    ↓
LIFE CUE EXTRACTS WHAT IT CAN
    ↓
REVIEW / CORRECT
    ↓
CREATE REMINDER
    ↓
LIFE CUE REMEMBERS
    ↓
NOTIFY
    ↓
DONE / SNOOZE / EDIT / FORWARD
```

The user should not have to understand: - databases - contexts -
reminder rules - AI - OCR - profiles - family structures

to use the basic product.

------------------------------------------------------------------------

# 4. Home Screen

The Home screen answers:

> What do I need to pay attention to?

Suggested structure:

``` text
Good morning, [Name]

TODAY

Doctor appointment
Sanchit · 4:00 PM

Science project
Due today

UPCOMING

Car insurance
18 September

                         +

────────────────────────────────
Home      Calendar      People   More
```

## Rules

-   No dashboard statistics.
-   No excessive filters.
-   No mandatory categories.
-   No mandatory contexts.
-   The `+` action is the primary action.
-   Home is the primary reminder view.

------------------------------------------------------------------------

# 5. Main Navigation

Four areas:

1.  Home
2.  Calendar
3.  People
4.  More

The `+` capture/add action must be easily accessible.

## Home

-   Today
-   Upcoming
-   Overdue
-   Attention-required reminders

## Calendar

-   Lightweight month view
-   Reminder indicators
-   Selected date's reminders

## People

-   Optional family/person organization

## More

-   Notification settings
-   Reminder defaults
-   Contexts
-   Privacy
-   Appearance
-   Data/account settings if later required
-   About

------------------------------------------------------------------------

# 6. Add / Capture

Tap `+`.

Show only the core choices:

``` text
ADD SOMETHING

[ Upload Image ]
Extract information from an image

[ Take Photo ]
Capture a document/photo

[ Add Reminder ]
Enter manually
```

Do not overload this screen.

Voice input is not required for V1.

------------------------------------------------------------------------

# 7. Incoming Image Policy

## Critical product decision

LifeCue MUST NOT register as an incoming iOS Share Sheet destination in
V1.

The user must enter LifeCue and select/upload the image from within
LifeCue.

Supported: - Photos Picker - Take Photo

Not supported: - WhatsApp → Share → LifeCue - Gmail → Share → LifeCue -
Photos → Share → LifeCue - any other external app → Share → LifeCue

This is intentional.

The product may support **outgoing Forward**, which is completely
different.

------------------------------------------------------------------------

# 8. Image Extraction Architecture --- No Paid AI

This is a firm V1 requirement.

## No cloud AI

Do NOT use: - OpenAI API - Anthropic API - Gemini API - any paid/cloud
LLM - any paid OCR service

for V1 screenshot extraction.

## Preferred pipeline

``` text
Image
  ↓
Apple Vision OCR
  ↓
Recognized text
  ↓
Local deterministic extraction/parsing
  ↓
Draft Reminder
  ↓
Review/Edit
  ↓
User confirms
```

Use Apple's on-device Vision text-recognition capability, subject to the
supported iOS deployment target and official Apple API documentation.

## Principle

> **Extract what can be reliably identified. Never invent what cannot be
> identified.**

------------------------------------------------------------------------

# 9. Local Extraction

OCR produces text. Local parsing converts text into candidate reminder
fields.

Possible extraction targets: - title/action - date - time - person name
when clearly identifiable - deadline/expiration - recurrence phrases -
useful note/details

Use deterministic techniques and native Apple capabilities where
appropriate.

Examples:

``` text
25 August
25/08/2026
August 25
4 PM
16:00
every year
annually
every Monday
due
deadline
expires
appointment
submit
```

Do not build an uncontrolled "AI-like" parser.

Keep the extraction layer: - deterministic - testable - explainable -
replaceable

------------------------------------------------------------------------

# 10. Extraction Failure Behavior

This is critical.

## Case A --- Everything extracted correctly

Show extracted fields on Review.

## Case B --- Partial extraction

Show whatever was extracted.

Example:

``` text
What
Doctor Appointment

For
Sanchit

Date
18 September

Time
4:00 PM

Note
[ Add note ]
```

Then:

> **Some information could not be identified from the image. Please
> check the details.**

The user can fill missing information.

## Case C --- OCR cannot read enough

Show:

> **We couldn't read enough information from this image.**

Actions: - Try another image - Add Reminder Manually

## Case D --- OCR text exists but no reminder-worthy structure is found

Show the recognized text or a useful extraction preview and allow the
user to create a reminder manually.

Never fabricate a reminder.

------------------------------------------------------------------------

# 11. Review & Confirmation

Every image-derived reminder is a **draft**.

Example:

``` text
REVIEW REMINDER

What
[ Science Project ]

Date
[ 25 August ]

Time
[ — ]

For
[ Sanchit ]

Note
[ Bring cardboard and 2 photographs. ]

Remind me
[ 1 week before · 1 day before ]

[ CREATE REMINDER ]
```

## Rules

-   User can edit every important field.
-   User can remove incorrect fields.
-   User can add missing information.
-   User must explicitly press `Create Reminder`.
-   No notification is scheduled before confirmation.
-   AI is not involved because V1 has no cloud AI.

------------------------------------------------------------------------

# 12. Notes

Every reminder supports an optional note.

Examples: - Take previous reports. - Ask about test results. - Buy
cardboard. - Call Rahul if payment is not received.

Notes are: - editable - optional - visible in reminder details -
included in Forward by default if present, but user can edit the
outgoing text.

------------------------------------------------------------------------

# 13. Reminder Model

Minimum: - title - event/due date OR explicit reminder date/time -
reminder schedule

Optional: - event time - note - person - context - source - category -
recurrence/rules - status

A user must be able to create a reminder without: - person - family -
context - category

------------------------------------------------------------------------

# 14. People

People are optional.

Example:

``` text
Me
Saachi
Sanchit
Mom
Partner
```

A reminder may optionally be linked to a person.

Example:

``` text
Doctor appointment
Person: Sanchit
```

No family setup is required.

------------------------------------------------------------------------

# 15. Contexts

Contexts are optional organizational metadata.

Examples: - Home - Work - School - Health - Car - Travel - Personal

## Person-specific contexts

Example:

``` text
Sanchit
  School
  Health
  Football

Saachi
  School
  Health
  Guitar
```

Sanchit's Health and Saachi's Health are separate context instances.

## Family/shared contexts

Possible later:

``` text
Family
  Home
  Car
  Vacation
```

Do not force users to create or manage contexts.

------------------------------------------------------------------------

# 16. Complexity Levels

### Level 1 --- Normal user

``` text
Reminder
```

### Level 2 --- Organized user

``` text
Reminder + Context
```

### Level 3 --- Family/power user

``` text
Reminder + Person + Context
```

The app should grow in capability without forcing complexity.

------------------------------------------------------------------------

# 17. Reminder Scheduling Engine

This is a core module.

Support:

## Exact time

``` text
18 September, 4 PM
```

## Before event

-   minutes before
-   hours before
-   days before
-   weeks before
-   months before where appropriate

## Multiple reminders

Example:

``` text
Event: 30 September

60 days before
30 days before
14 days before
7 days before
1 day before
```

## Recurrence

-   daily
-   weekly
-   monthly
-   yearly
-   custom recurrence where feasible

## Date window

Example:

``` text
Start: 1 September
End: 15 September
Every 2 days
9:00 AM
```

## Stop conditions

-   one occurrence
-   after completion
-   after end date
-   configured number of occurrences where supported

The rule engine must calculate occurrences deterministically and be
heavily unit tested.

------------------------------------------------------------------------

# 18. Reminder UI

Default scheduling UI should remain simple:

``` text
Remind me
1 week before · 1 day before
```

Advanced:

``` text
Reminder Schedule

Suggested
● 1 week before
● 1 day before

+ Add another reminder

Custom
Specific date
Before event
Between dates
Repeat
Until completed
```

Do not show all advanced controls on the first screen.

------------------------------------------------------------------------

# 19. Yearly Reminders

Yearly reminders are explicitly supported.

Example:

``` text
Annual medical test
Every year
```

LifeCue is only scheduling the reminder.

It must not state that a particular medical test is medically necessary.

------------------------------------------------------------------------

# 20. Notifications

Use local iOS notifications for ordinary reminders.

Conceptually:

``` text
Reminder
  ↓
Rule engine
  ↓
Calculated occurrences
  ↓
UserNotifications
```

No server is required for ordinary notification scheduling.

Support: - permission request at appropriate time - schedule - cancel -
reschedule - completion cancellation - deletion cancellation -
recurrence scheduling

------------------------------------------------------------------------

# 21. Snooze / Complete / Reschedule

Reminder actions: - Complete - Snooze - Reschedule - Edit - Delete -
Forward

Snooze should have simple options such as: - later today - tomorrow -
next week - custom

------------------------------------------------------------------------

# 22. Forward Feature

The feature is called **Forward**, not Share.

## Purpose

Send reminder details to another person.

## Important distinction

### Incoming

LifeCue does NOT appear in other apps' Share Sheets.

### Outgoing

LifeCue can send an existing reminder through the iOS system sharing
interface.

## Flow

``` text
Reminder
  ↓
Forward
  ↓
LifeCue generates plain text locally
  ↓
User reviews/edits
  ↓
iOS system sharing
  ↓
User chooses Messages / WhatsApp / Mail / etc.
```

## No AI

Forward MUST NOT use AI.

Generate deterministic text from: - title - person if present - date -
time if present - note if present

Example:

``` text
Doctor Appointment
Sanchit
18 September at 4:00 PM

Take previous reports.
```

If a field is missing, omit it.

## User editing

The generated message must be editable before forwarding.

## No direct integrations

Do not implement: - WhatsApp API - Gmail API - automatic sending -
recipient selection - background forwarding

Use the iOS system sharing mechanism.

------------------------------------------------------------------------

# 23. Calendar

Lightweight calendar only.

Support: - month view - date selection - reminder indicators - reminder
list for selected date - open reminder detail

Do not replace Apple Calendar.

------------------------------------------------------------------------

# 24. Source Image

For image-created reminders, the app may retain a local reference to the
source image if practical and privacy-safe.

Reminder can show:

``` text
Source
View Original
```

Deleting the source must not delete/corrupt the reminder.

Do not retain images unnecessarily.

------------------------------------------------------------------------

# 25. Backend Decision

## V1: No backend required.

Because V1 uses: - on-device OCR - local parsing - local reminder
persistence - local notifications - local Forward formatting

Therefore:

``` text
iOS App
  ├── OCR
  ├── Local extraction
  ├── Local database
  ├── Reminder engine
  ├── Notifications
  └── Forward
```

No server is required.

## Future backend

A backend may become useful for: - account synchronization -
cross-device sync - Android sync - family sharing - cloud backup -
remote/conditional monitoring - subscriptions - analytics - future AI,
if ever deliberately introduced

Do not build any of this in V1 unless separately approved.

------------------------------------------------------------------------

# 26. Persistence

Use local Apple-native persistence appropriate for the supported iOS
deployment target.

The implementation agent must verify current Apple documentation before
selecting the persistence technology.

Do not introduce PostgreSQL or another remote database for V1.

------------------------------------------------------------------------

# 27. Conceptual Data Model

``` text
User / Local Profile
   │
   ├── People (optional)
   │      └── Contexts (optional)
   │
   ├── Family/Shared Contexts (future/optional)
   │
   └── Reminders
          ├── Reminder Rules
          ├── Reminder Occurrences
          └── Source (optional)
```

Possible reminder fields:

``` text
id
title
eventDate
eventTime
timezone
note
status
personID?
contextID?
sourceID?
createdAt
updatedAt
completedAt?
```

Possible rule fields:

``` text
id
reminderID
ruleType
offsetValue?
offsetUnit?
startDate?
endDate?
timeOfDay?
recurrencePattern?
stopCondition?
enabled
```

Exact implementation should be reviewed against the chosen persistence
framework.

------------------------------------------------------------------------

# 28. Date/Time Requirements

Never store dates internally as ambiguous display strings.

Distinguish: - event date - event time - reminder occurrence date -
reminder occurrence time - timezone

Test: - tomorrow - next Monday - month boundary - year boundary - leap
years - yearly recurrence - daylight saving where relevant -
locale-specific date formats

For India-first V1, use the device timezone unless the user explicitly
specifies another timezone.

------------------------------------------------------------------------

# 29. Privacy

Potential inputs may contain: - children's names - school information -
medical appointment information - bills - addresses - workplace
information

V1 should minimize data movement.

Preferred: - OCR on device - local parsing - local reminder storage - no
cloud upload required for extraction

Do not log full OCR contents or screenshots in production.

Request permissions only when needed.

------------------------------------------------------------------------

# 30. Permissions

Potential permissions: - Photos: when user chooses an image - Camera:
when user takes a photo - Notifications: when user enables reminders

Do not request all permissions on first launch without a user need.

------------------------------------------------------------------------

# 31. Onboarding

Keep onboarding short.

Example:

``` text
Welcome to LifeCue

Capture what you don't want to forget.

[ Continue ]
```

Notification permission should be requested at a contextually
appropriate moment.

Do not force: - family creation - People creation - Context creation -
categories - account setup unless later required

------------------------------------------------------------------------

# 32. UI Design Direction

Modern, simple, calm, iOS-native.

Use: - generous whitespace - clear typography - rounded cards - one
primary accent - subtle icons - minimal navigation - strong information
hierarchy

Avoid: - dashboard overload - excessive colors - excessive cards -
complex productivity terminology - mandatory metadata - copied UI from
another product

Design inspiration can be drawn from simple Apple/Google
family-management patterns without copying them.

------------------------------------------------------------------------

# 33. App Name

Working name:

# LifeCue

Possible positioning: - Capture it. We'll remind you. - Never forget
what matters. - Your life. Remembered.

Before launch: - check App Store conflicts - trademark search - domain
availability - existing company/app conflicts

------------------------------------------------------------------------

# 34. V1 Modules

1.  Home
2.  Reminder CRUD
3.  Capture
4.  Apple Vision OCR
5.  Local extraction/parser
6.  Review/confirmation
7.  Reminder rules
8.  Local notifications
9.  Notes
10. People
11. Contexts
12. Calendar
13. Forward
14. Source handling
15. Settings

------------------------------------------------------------------------

# 35. Development Sequence

### Sprint 1

Foundation + manual reminders + local persistence

### Sprint 2

Notifications + reminder engine foundation

### Sprint 3

Image capture + Apple Vision OCR

### Sprint 4

Local smart extraction/parser

### Sprint 5

Review/confirmation + extraction failure UX

### Sprint 6

Advanced reminder rules

### Sprint 7

People + Contexts + Calendar

### Sprint 8

Forward

### Sprint 9

Hardening + tests + TestFlight/App Store preparation

------------------------------------------------------------------------

# 36. Definition of Done

V1 is complete when: - manual reminders work - local persistence works -
notifications work - image capture works - OCR works - local extraction
works for supported cases - extraction failure is transparent - user can
correct all extracted fields - confirmation is mandatory - notes work -
multiple reminders work - yearly reminders work - date-window reminders
work - People remain optional - Contexts remain optional - Calendar
works - Forward works without AI - incoming Share Extension does not
exist - no cloud AI is used - no backend is required - sensitive content
is not unnecessarily logged - critical tests pass - release build is
stable

------------------------------------------------------------------------

# 37. Product North Star

LifeCue is not: - a full project manager - a family ERP - a
medical-record system - a calendar replacement - an AI chatbot

LifeCue is:

> **A simple system that captures real-world things people don't want to
> forget and reminds them at the right time.**
