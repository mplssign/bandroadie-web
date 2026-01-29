-- Temporarily disable the rehearsal notification trigger
-- Run this in Supabase SQL Editor to allow rehearsal creation while we debug

DROP TRIGGER IF EXISTS rehearsal_created_notification ON rehearsals;
