-- ============================================================================
-- Migration: add_company_to_contacts
-- Adds an optional company/affiliation field to standalone contacts.
-- ============================================================================

ALTER TABLE public.contacts ADD COLUMN company TEXT;
