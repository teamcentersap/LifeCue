# LifeCue Backup Format (v1)

Portable, local-first backup contract for LifeCue.

This document is the cross-platform data contract. Android may implement the same format later without reverse-engineering iOS.

## File

- Extension: `.lifecuebackup`
- UTI: `com.lifecue.backup`
- Encoding: UTF-8 JSON
- Mime/role: opaque portable document (conforms to `public.data`)

Example filename: `LifeCue Backup 2026-08-12.lifecuebackup`

## Envelope

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `format` | string | yes | Must be exactly `LifeCueBackup` |
| `schemaVersion` | int | yes | Data-contract version. **Not** the app marketing version. Current: `1` |
| `minimumReaderVersion` | int | yes | Oldest reader that can safely import. Current: `1` |
| `exportedAt` | string | yes | ISO-8601 UTC timestamp |
| `people` | array | yes | May be empty |
| `contexts` | array | yes | May be empty |
| `reminders` | array | yes | May be empty |

## Version rules

- Older backup → newer app: migrate (v1 is identity).
- Newer unsupported backup (`schemaVersion` or `minimumReaderVersion` above the app’s max): **reject entirely**. Never partial import. Never silently strip required behavior.
- Unsupported / invalid backups must leave existing device data unchanged.

## UUID / date / timezone encoding

- UUID: canonical hyphenated string (JSON UUID).
- Instants (`exportedAt`, `createdAt`, `updatedAt`, `completedAt`, `snooze.until`): ISO-8601 UTC (`YYYY-MM-DDTHH:mm:ss.sssZ` preferred; without fractional seconds accepted).
- Calendar dates: `{ "year": 2026, "month": 8, "day": 15 }` (explicit ints; not locale display strings).
- Times: `{ "hour": 16, "minute": 0 }` (24-hour). Omit `eventTime` for date-only reminders.
- Time zones: IANA identifiers, e.g. `Asia/Kolkata`. Reminder wall-clock TZ must be preserved.

## People

| Field | Required |
|-------|----------|
| `id` | yes |
| `name` | yes (non-empty) |
| `relationship` | no |
| `iconName` | no |
| `colorToken` | no |
| `isArchived` | yes |
| `createdAt` | yes |
| `updatedAt` | yes |

Do **not** include phone, email, address, DOB, medical, or school details.

Archived people are exported and restored as archived (historical reminder FKs).

## Contexts

| Field | Required |
|-------|----------|
| `id` | yes |
| `name` | yes (non-empty) |
| `personID` | no (nil = global) |
| `iconName` | no |
| `colorToken` | no |
| `isArchived` | yes |
| `createdAt` | yes |
| `updatedAt` | yes |

Identity is by `id`, never by name. Person-specific contexts remain distinct across people (`Child1→Doctor` ≠ `Child2→Doctor`).

If `personID` is set, that Person must exist in the same backup.

## Reminders

| Field | Required |
|-------|----------|
| `id` | yes |
| `title` | yes (non-empty) |
| `eventDate` | yes |
| `eventTime` | no |
| `timeZoneIdentifier` | yes (valid IANA) |
| `note` | no |
| `personID` | no |
| `contextID` | no |
| `status` | yes (`active` \| `completed`) |
| `rules` | yes (array; may be empty) |
| `snooze` | no (`{ "until": "<ISO-8601 UTC>" }`) |
| `createdAt` | yes |
| `updatedAt` | yes |
| `completedAt` | no |

### Status

- `active` / `completed` are persistent domain state and are restored.
- Hard-deleted reminders are absent from the store and therefore absent from backups.

### Snooze

- Persistent `until` instant only.
- Do not export notification request IDs.
- After import, the app rebuilds scheduling from domain state; expired snooze is cleared by existing reconcile behavior.

### Rules

| Field | Notes |
|-------|-------|
| `id` | UUID; preserved |
| `ruleType` | `exactAtEvent` \| `beforeEvent` \| `recurring` (legacy `snoozeOneOff` / `dateWindow` reserved) |
| `offsetValue` / `offsetUnit` | for `beforeEvent` (`minute`\|`hour`\|`day`\|`week`\|`month`) |
| `enabled` | bool |
| `recurrence` | for recurring |
| `dateWindow` | optional inclusive `{ startDate, endDate }` |

Recurrence:

| Field | Notes |
|-------|-------|
| `frequency` | `daily` \| `weekly` \| `monthly` \| `yearly` |
| `interval` | int ≥ 1 |
| `weekdays` | optional; Calendar convention 1=Sunday … 7=Saturday |
| `dayOfMonth` | optional 1…31 |

Date-only product rule (not encoded separately): missing `eventTime` → notification fire uses **09:00** in the reminder’s stored timezone after restore (existing engine policy).

## Relationship rules

- `Reminder.personID` nil or an imported Person.
- `Reminder.contextID` nil or an imported Context.
- If Context has `personID`, Reminder’s `personID` must equal that Context’s `personID`.
- Corrupted relationships → reject entire backup (no silent repair).

## Intentionally excluded

- `UNNotificationRequest` / notification identifiers / generations
- EventKit events / IDs / permissions
- SwiftData internals
- OCR images / drafts
- UI / device / Apple Account identifiers
- Cloud credentials

## Import modes (iOS v1)

- **Replace only** (explicit user confirmation).
- Merge deferred (not part of v1 contract).

## Notification rebuild

Backup restores domain data only. After a successful replace, the host app rebuilds local notifications through its normal scheduling path. Notification IDs are device-local and newly generated.
