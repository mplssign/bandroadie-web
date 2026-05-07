-- Add is_potential column to rehearsals table
-- Implements rehearsal potential toggle feature
-- Default FALSE maintains backward compatibility with existing rehearsal behavior

ALTER TABLE public.rehearsals 
ADD COLUMN is_potential BOOLEAN NOT NULL DEFAULT FALSE;

-- Create index for efficient filtering by potential status
CREATE INDEX idx_rehearsals_is_potential ON public.rehearsals(is_potential);
