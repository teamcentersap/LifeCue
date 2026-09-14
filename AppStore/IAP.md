# LifeCue Pro Lifetime

Non-consumable lifetime unlock for LifeCue **1.1.0 (3)**.

## App Store Connect

| Field | Value |
|--------|--------|
| Type | Non-Consumable |
| Reference Name | LifeCue Pro Lifetime |
| Product ID | `com.lifecue.app.pro.lifetime` |
| Display Name | LifeCue Pro Lifetime |
| Description (45 max) | `Lifetime unlock for LifeCue Pro tools.` |
| Price | Set in App Store Connect (StoreKit local default $9.99) |

Product ID cannot be changed after you create it. Use this ID exactly.

Screenshot: `AppStore/IAP-Screenshot.png` (1242 x 2208, RGB, no alpha). Do not put a price in the screenshot.

## Free

Manual reminders, notes, one-time notifications, snooze / complete / edit, optional People and Contexts, Home, Calendar.

## Pro

Upload Image, Take Photo, on-device extraction, repeating / yearly / date-window reminders, Forward, Backup and Restore.

Existing repeating reminders keep working if they were already saved.

## Submit

1. Paid Apps agreement must be Active.
2. Create the IAP with the product ID above.
3. Add English (U.S.) localization, paste name and description, upload `IAP-Screenshot.png`.
4. Create version **1.1.0** in App Store Connect and attach this IAP on the version page.
5. Archive **1.1.0 (3)**, upload, paste What's New and review notes, submit **1.1.0**. Do not submit the IAP page by itself.

Local Xcode testing uses `LifeCue/Resources/Configuration.storekit`.
