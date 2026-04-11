# Feature Input — BandRoadie

## Feature Identifier (REQUIRED)

`feature/backup-member-access-and-scheduled`

---

## Type (REQUIRED)

`feature`

---

## Title (REQUIRED)

Expand Backup Access to All Members and Add Scheduled Auto-Backup with Email Delivery

---

## Summary (REQUIRED)

**What the user is trying to do:**

Two related enhancements to the existing Data Backup system:

**1. Member-level export access**
Currently, the data export (band backup) is restricted to admins only. Any active band member should be able to trigger a read-only export of their band's data at any time. This ensures that if an admin is unavailable or the service is ever discontinued, any member can retrieve the band's data independently. The export scope and format remain identical to the existing admin export — read-only JSON snapshot. This does not grant members any new write or import capabilities.

**2. Scheduled automatic backup with email delivery**
Users currently must remember to manually export their band data. A scheduled backup system should allow each user to configure an email address to receive a band data backup automatically. The user controls:
- A destination email address (can differ from their login email)
- Backup frequency: Daily or Weekly

The system should send the backup JSON as an email attachment to the configured address on the chosen schedule. Each user's schedule is independent — one member may configure weekly, another daily, and others may opt out entirely. Configuration lives in user settings (per-band or global is at Architect's discretion based on data model fit).

The backup email should include:
- Band name and export date in the subject line
- A brief plain-text body indicating what is included and how to restore it
- The `.json` backup file as an attachment

**Why the change is needed:**
Manual-only backups place the burden of data safety entirely on the user remembering to act. Scheduled backups provide a passive safety net. Member-level access closes a gap where a band could lose all data access if the sole admin becomes unavailable.

**Known constraints:**
- The existing `DataBackupService` handles export logic — the Architect should extend it rather than replace it
- Email delivery requires a new Supabase Edge Function (or extension of an existing one) using the existing Resend integration
- Scheduled execution should use Supabase's pg_cron or equivalent — do not introduce a new external scheduling service
- The backup JSON format (schema version 1) must not change
- Import/restore capability remains admin-only — this feature expands export only, not import

---

## Reproduction Steps

*(Not applicable — new feature)*

---

## Expected Behavior (REQUIRED)

**Member export access:**
- Any active band member (role: `admin`, `member`, or `contributor` with appropriate permissions) can trigger an export of their band's data from the Settings screen
- The export button or option is visible to all active members, not just admins
- Export produces the same JSON output as the current admin export
- Import/restore remains admin-only and is not affected

**Scheduled backup:**
- In Settings, users see a "Scheduled Backup" section
- User can enter or update a destination email address for backups
- User can select frequency: Daily or Weekly
- User can disable scheduled backup (opt-out / off state)
- At the configured interval, the system sends the band data backup JSON as an email attachment to the configured address
- Email subject: `BandRoadie Backup — [Band Name] — [Date]`
- Email body: brief plain-text explanation of contents and restore instructions
- Attachment filename follows the existing naming convention: `bandroadie_<band_name>_<date>.json`
- If the backup fails to send, it should not silently disappear — log the failure

---

## Affected Platforms

`Web` / `iOS` / `Android` / `macOS`

---

## Additional Context (OPTIONAL)

- Existing backup implementation: `lib/features/settings/data_backup_service.dart`
- Web download variant: `lib/features/settings/data_backup_web.dart`
- Existing email integration: Resend (used for transactional emails — see deployment and supabase function docs)
- The backup explicitly excludes `device_tokens`, `notifications`, and `band_calendar_subscriptions` — this exclusion must be preserved
- Architect should evaluate whether scheduled backup config is stored per-user globally or scoped per band-member relationship, and document the decision with rationale
- The Architect should assess whether the scheduled send should use a Supabase database trigger + pg_cron job, or a dedicated Edge Function invoked on a schedule
- Reference docs: `docs/reference/deployment/deployment.md`, `docs/reference/architecture/supabase_functions.md`
