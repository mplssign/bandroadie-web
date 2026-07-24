-- Add index on device_tokens.last_seen for 48-hour freshness queries
CREATE INDEX idx_device_tokens_last_seen ON device_tokens(last_seen);

-- Add indexes on unindexed FK columns to optimize joins and FK constraint checks during deletes

-- 1. band_calendar_subscriptions.band_id
CREATE INDEX idx_band_calendar_subscriptions_band_id
  ON band_calendar_subscriptions(band_id);

-- 2. band_invitations.invited_by
CREATE INDEX idx_band_invitations_invited_by
  ON band_invitations(invited_by);

-- 3. bands.created_by
CREATE INDEX idx_bands_created_by
  ON bands(created_by);

-- 4. bands.last_used_print_template_id
CREATE INDEX idx_bands_last_used_print_template_id
  ON bands(last_used_print_template_id);

-- 5. gig_responses.user_id
CREATE INDEX idx_gig_responses_user_id
  ON gig_responses(user_id);

-- 6. gigs.created_by
CREATE INDEX idx_gigs_created_by
  ON gigs(created_by);

-- 7. notifications.actor_user_id
CREATE INDEX idx_notifications_actor_user_id
  ON notifications(actor_user_id);

-- 8. rehearsal_responses.rehearsal_date_id
CREATE INDEX idx_rehearsal_responses_rehearsal_date_id
  ON rehearsal_responses(rehearsal_date_id);

-- 9. rehearsal_responses.user_id
CREATE INDEX idx_rehearsal_responses_user_id
  ON rehearsal_responses(user_id);

-- 10. setlists.created_by
CREATE INDEX idx_setlists_created_by
  ON setlists(created_by);

-- Remove duplicate indexes after verifying dependencies

-- Before dropping, verify these indexes are not referenced by constraints or application code:
-- SELECT conname, conindid::regclass
-- FROM pg_constraint
-- WHERE conindid IN (
--   'band_members_band_id_user_id_key'::regclass,
--   'gig_responses_gig_user_date_unique'::regclass
-- );

-- Drop one index from each identical pair (keep the more descriptive name)
-- band_members: drop the constraint (which will drop its index)
-- gig_responses: drop the index directly (no constraint)
ALTER TABLE band_members DROP CONSTRAINT IF EXISTS band_members_band_user_unique;
DROP INDEX IF EXISTS gig_responses_gig_user_date_unique;
