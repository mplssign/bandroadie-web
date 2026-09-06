-- Normalize gig addresses for all demo template + clone bands.
-- This catches existing cloned demo sessions that use random UUIDs and were not
-- covered by deterministic template-gig ID updates.

UPDATE public.gigs AS g
SET address = CASE g.location
  -- Banana Stand venues
  WHEN 'Yacht Club Newport Beach' THEN '110 Newport Center Dr'
  WHEN 'Newport Beach Convention Center' THEN '4333 MacArthur Blvd'
  WHEN 'Balboa Island Park' THEN '124 Agate Ave'
  WHEN 'Sudden Valley Model Home' THEN '24601 Sudden Valley Rd'

  -- Modal Nodes venues
  WHEN 'Chalmun''s Cantina' THEN '7 Cantina Row'
  WHEN 'Mos Eisley Spaceport' THEN 'Hangar Bay 94'
  WHEN 'Jabba''s Palace' THEN 'Great Pit of Carkoon Rd'
  WHEN 'Cloud City Ballroom' THEN 'Level 22 Bespin Tower'
  ELSE g.address
END
FROM public.bands AS b
WHERE g.band_id = b.id
  AND (b.is_demo_template = true OR b.is_demo_clone = true)
  AND g.location IN (
    'Yacht Club Newport Beach',
    'Newport Beach Convention Center',
    'Balboa Island Park',
    'Sudden Valley Model Home',
    'Chalmun''s Cantina',
    'Mos Eisley Spaceport',
    'Jabba''s Palace',
    'Cloud City Ballroom'
  );
