-- ============================================================================
-- Migration: Tighten financial_entries RLS to admin & member only
-- Date: 2026-07-11
-- Branch: feature/expense-delete-drawer
-- Revision: Post-QA RBAC fix
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 1: Replace INSERT policy
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "financial_entries_insert" ON public.financial_entries;

CREATE POLICY "Admins and members can create financial entries"
  ON public.financial_entries
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = financial_entries.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
    AND created_by = auth.uid()
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 2: Replace DELETE policy
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "financial_entries_delete" ON public.financial_entries;

CREATE POLICY "Admins and members can delete financial entries"
  ON public.financial_entries
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = financial_entries.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 3: Replace UPDATE policy (admin & member only)
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "financial_entries_update" ON public.financial_entries;

CREATE POLICY "Admins and members can update financial entries"
  ON public.financial_entries
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = financial_entries.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = financial_entries.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- Note: SELECT policy unchanged — Contributors with can_view_financials = true
-- can still view entries. This migration only restricts INSERT/UPDATE/DELETE.
-- ═══════════════════════════════════════════════════════════════════════════
