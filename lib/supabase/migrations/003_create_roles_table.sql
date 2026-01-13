-- Migration: create global roles table

CREATE TABLE IF NOT EXISTS public.roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Index for case-insensitive lookups
CREATE UNIQUE INDEX IF NOT EXISTS roles_name_ci_idx ON public.roles(LOWER(name));
