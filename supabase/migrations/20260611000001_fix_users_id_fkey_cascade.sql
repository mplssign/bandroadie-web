-- Fix users_id_fkey to cascade on auth user deletion.
-- Previously RESTRICT, which blocked dashboard user deletions.
ALTER TABLE public.users DROP CONSTRAINT users_id_fkey;
ALTER TABLE public.users ADD CONSTRAINT users_id_fkey
  FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
