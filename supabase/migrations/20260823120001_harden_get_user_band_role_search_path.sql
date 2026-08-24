-- ============================================================================
-- Add SET search_path to get_user_band_role function
-- ============================================================================
-- Feature: rls-policy-performance-hardening
-- Issue: get_user_band_role was created without SET search_path and missed
--        during Aug 14, 2026 search_path hardening sweep
-- Fix: Add immutable search_path via ALTER FUNCTION
-- ============================================================================
-- Security Advisor: 1 function_search_path_mutable warning
-- Created: 20260302000000_band_user_roles.sql
-- Last modified: Never
-- ============================================================================

ALTER FUNCTION public.get_user_band_role(uuid) SET search_path = public;

-- ===========================================================================
-- ROLLBACK
-- ===========================================================================
-- ALTER FUNCTION public.get_user_band_role(uuid) RESET search_path;
