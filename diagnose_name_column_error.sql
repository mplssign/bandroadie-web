-- Comprehensive diagnostic to find what's referencing "name" column
-- Run this in Supabase SQL Editor

-- 1. Check ALL triggers on rehearsals table
SELECT 
  trigger_name,
  event_manipulation,
  action_timing,
  action_statement
FROM information_schema.triggers
WHERE event_object_table = 'rehearsals'
ORDER BY trigger_name;

-- 2. Check RLS policies on rehearsals (might reference name in conditions)
SELECT 
  schemaname,
  tablename,
  policyname,
  cmd
FROM pg_policies
WHERE tablename = 'rehearsals';

-- 3. Verify rehearsals schema (confirm no name column)
SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'rehearsals'
ORDER BY ordinal_position;

-- 4. Check for views that reference rehearsals
SELECT 
  table_name,
  view_definition
FROM information_schema.views
WHERE view_definition LIKE '%rehearsals%'
  AND table_schema = 'public';

-- 5. Search all functions for references to rehearsals.name
SELECT 
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_functiondef(p.oid) as function_definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE pg_get_functiondef(p.oid) ILIKE '%rehearsals%'
  AND pg_get_functiondef(p.oid) ILIKE '%name%'
  AND n.nspname = 'public'
ORDER BY p.proname;
