CREATE OR REPLACE FUNCTION public.sync_gig_location_from_venue()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.gigs
  SET
    location = COALESCE(NULLIF(NEW.city, ''), location),
    address = NEW.address,
    state = NEW.state,
    updated_at = now()
  WHERE venue_id = NEW.id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_gig_location_from_venue ON public.venues;

CREATE TRIGGER trg_sync_gig_location_from_venue
  AFTER UPDATE ON public.venues
  FOR EACH ROW
  WHEN (
    OLD.city IS DISTINCT FROM NEW.city OR
    OLD.address IS DISTINCT FROM NEW.address OR
    OLD.state IS DISTINCT FROM NEW.state
  )
  EXECUTE FUNCTION public.sync_gig_location_from_venue();

UPDATE public.gigs g
SET
  location = COALESCE(NULLIF(v.city, ''), g.location),
  address = v.address,
  state = v.state,
  updated_at = now()
FROM public.venues v
WHERE g.venue_id = v.id
  AND (
    g.location IS DISTINCT FROM v.city OR
    g.address IS DISTINCT FROM v.address OR
    g.state IS DISTINCT FROM v.state
  );
