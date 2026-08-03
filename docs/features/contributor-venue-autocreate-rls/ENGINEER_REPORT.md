# Engineer Report

## Feature Slug

bug/contributor-venue-autocreate-rls

## Feature Title

Contributor venue auto-create RLS fix

## Goal

Implement a scoped venue auto-create path for gig save that works for authorized contributors without loosening direct `venues` table RLS, and stop silent save continuation when venue auto-create fails.

## Architect Tasks Completed

- [x] Task 1 — Created migration `supabase/migrations/20260802133000_create_venue_for_gig_save_rpc.sql`.
- [x] Task 2 — Implemented `public.create_venue_for_gig_save(...)` with input validation, role/sub-permission authorization, SECURITY DEFINER, search path, dedupe, and grant to authenticated.
- [x] Task 3 — Added `createVenueForGigSave(...)` to `VenuesRepository` using `supabase.rpc(...)`.
- [x] Task 4 — Added `createForGigSave(...)` to `VenuesNotifier`, with cache reload and error rethrow.
- [x] Task 5 — Updated `EventEditorDrawer._handleSave()` to call `createForGigSave(...)`.
- [x] Task 6 — Failure path now throws into existing outer save catch (no silent continue after auto-create attempt).
- [x] Task 7 — Ran verification SQL checks and `flutter analyze`.
- [x] Task 8 — Produced this report including complete diff text.

## Files Created

- `supabase/migrations/20260802133000_create_venue_for_gig_save_rpc.sql`
- `docs/features/contributor-venue-autocreate-rls/ENGINEER_REPORT.md`

## Files Modified

- `lib/features/contacts/venues_repository.dart`
- `lib/features/contacts/venues_controller.dart`
- `lib/features/events/widgets/event_editor_drawer.dart`

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 1 pre-existing info-level warning unrelated to this scope (`lib/features/setlists/setlist_detail_screen.dart:1449`, `use_build_context_synchronously`).

## Test Results

Not run (Architect plan did not require `flutter test`; required SQL verification was executed).

## Verification

Manual/SQL steps performed:

- Tier 1 pre-deploy check 1 (venues INSERT policy): policy remains `Admins and members can create venues`.
- Tier 1 pre-deploy check 2 (contributor permissions columns): `can_create_gigs` and `can_create_potential_gigs_only` both exist.
- Tier 1 pre-deploy check 3 (function pre-existence): no existing `create_venue_for_gig_save` found.
- Applied migration with `supabase db push --linked`.
- Tier 2 post-deploy check 1 (exact Architect query): returned `false` because PostgreSQL emits canonical text `SET search_path TO 'public'` in `pg_get_functiondef`.
- Tier 2 post-deploy check 1 (canonical-text equivalent): `has_security_definer = true`, `has_search_path_public = true`.
- Tier 2 post-deploy check 2: `has_function_privilege(..., 'EXECUTE') = true`.
- Tier 2 post-deploy check 3: recent gigs with typed location/name but null `venue_id` count returned `1`.

## Deviations From Architect Plan

- None in implementation scope.
- Verification note only: Architect check text for search path uses `LIKE '%search_path = public%'`; PostgreSQL function definition canonicalization produced `SET search_path TO 'public'`, so equivalent canonical check was added and passed.

## Blockers Encountered

- None.

## Ready For QA

Yes.

## Complete git diff

```diff
diff --git a/lib/features/contacts/venues_controller.dart b/lib/features/contacts/venues_controller.dart
index 4cf2111..0721a1c 100644
--- a/lib/features/contacts/venues_controller.dart
+++ b/lib/features/contacts/venues_controller.dart
@@ -116,6 +116,33 @@ class VenuesNotifier extends Notifier<VenuesState> {
     }
   }

+  Future<Venue> createForGigSave({
+    required String bandId,
+    required String name,
+    String? city,
+    String? address,
+    String? state,
+    required bool isPotential,
+  }) async {
+    try {
+      final venue = await _repository.createVenueForGigSave(
+        bandId: bandId,
+        name: name,
+        city: city,
+        address: address,
+        state: state,
+        isPotential: isPotential,
+      );
+      await load(bandId);
+      return venue;
+    } catch (e) {
+      if (kDebugMode) {
+        debugPrint('[VenuesController] Error creating venue for gig save: $e');
+      }
+      rethrow;
+    }
+  }
+
   Future<Venue?> update({
     required String id,
     required String bandId,
diff --git a/lib/features/contacts/venues_repository.dart b/lib/features/contacts/venues_repository.dart
index b452b4f..c6c37a1 100644
--- a/lib/features/contacts/venues_repository.dart
+++ b/lib/features/contacts/venues_repository.dart
@@ -84,6 +84,30 @@ class VenuesRepository {
     return Venue.fromJson(response);
   }

+  Future<Venue> createVenueForGigSave({
+    required String bandId,
+    required String name,
+    String? city,
+    String? address,
+    String? state,
+    required bool isPotential,
+  }) async {
+    final response = await supabase.rpc(
+      'create_venue_for_gig_save',
+      params: {
+        'p_band_id': bandId,
+        'p_name': name,
+        'p_city': city,
+        'p_address': address,
+        'p_state': state,
+        'p_is_potential': isPotential,
+      },
+    );
+
+    _invalidateCache(bandId);
+    return Venue.fromJson(Map<String, dynamic>.from(response as Map));
+  }
+
   Future<Venue> updateVenue({
     required String id,
     required Map<String, dynamic> data,
diff --git a/lib/features/events/widgets/event_editor_drawer.dart b/lib/features/events/widgets/event_editor_drawer.dart
index a0e4613..b5d156d 100644
--- a/lib/features/events/widgets/event_editor_drawer.dart
+++ b/lib/features/events/widgets/event_editor_drawer.dart
@@ -1444,23 +1444,22 @@ class _EventEditorDrawerState extends ConsumerState<EventEditorDrawer>
           formData = formData.copyWith(venueId: _selectedVenueId);
         } else {
           // No match — create new venue with all available fields
-          final newVenue = await ref.read(venuesProvider.notifier).create(
-            bandId: widget.bandId,
-            data: {
-              'name': venueName,
-              'city': venueCity.isNotEmpty ? venueCity : null,
-              'address': _addressController.text.trim().isNotEmpty
-                  ? _addressController.text.trim()
-                  : null,
-              'state': _stateController.text.trim().isNotEmpty
-                  ? _stateController.text.trim()
-                  : null,
-            },
-          );
-          if (newVenue != null) {
-            _selectedVenueId = newVenue.id;
-            formData = formData.copyWith(venueId: newVenue.id);
-          }
+          final newVenue = await ref
+              .read(venuesProvider.notifier)
+              .createForGigSave(
+                bandId: widget.bandId,
+                name: venueName,
+                city: venueCity.isNotEmpty ? venueCity : null,
+                address: _addressController.text.trim().isNotEmpty
+                    ? _addressController.text.trim()
+                    : null,
+                state: _stateController.text.trim().isNotEmpty
+                    ? _stateController.text.trim()
+                    : null,
+                isPotential: _isPotentialGig,
+              );
+          _selectedVenueId = newVenue.id;
+          formData = formData.copyWith(venueId: newVenue.id);
         }
       }

diff --git a/supabase/migrations/20260802133000_create_venue_for_gig_save_rpc.sql b/supabase/migrations/20260802133000_create_venue_for_gig_save_rpc.sql
new file mode 100644
index 0000000..68c54dc
--- /dev/null
+++ b/supabase/migrations/20260802133000_create_venue_for_gig_save_rpc.sql
@@ -0,0 +1,101 @@
+CREATE OR REPLACE FUNCTION public.create_venue_for_gig_save(
+  p_band_id UUID,
+  p_name TEXT,
+  p_city TEXT DEFAULT NULL,
+  p_address TEXT DEFAULT NULL,
+  p_state TEXT DEFAULT NULL,
+  p_is_potential BOOLEAN DEFAULT FALSE
+)
+RETURNS public.venues
+LANGUAGE plpgsql
+SECURITY DEFINER
+SET search_path = public
+AS $$
+DECLARE
+  v_user_id UUID := auth.uid();
+  v_member RECORD;
+  v_can_create BOOLEAN := FALSE;
+  v_name TEXT;
+  v_city TEXT;
+  v_existing public.venues%ROWTYPE;
+  v_created public.venues%ROWTYPE;
+BEGIN
+  IF v_user_id IS NULL THEN
+    RAISE EXCEPTION 'Not authenticated';
+  END IF;
+
+  IF p_band_id IS NULL THEN
+    RAISE EXCEPTION 'band_id is required';
+  END IF;
+
+  v_name := NULLIF(trim(p_name), '');
+  IF v_name IS NULL THEN
+    RAISE EXCEPTION 'name is required';
+  END IF;
+
+  v_city := NULLIF(trim(p_city), '');
+
+  SELECT bm.id, bm.role
+  INTO v_member
+  FROM public.band_members bm
+  WHERE bm.band_id = p_band_id
+    AND bm.user_id = v_user_id
+    AND bm.status = 'active'
+  LIMIT 1;
+
+  IF v_member IS NULL THEN
+    RAISE EXCEPTION 'User is not an active member of this band';
+  END IF;
+
+  IF v_member.role IN ('admin', 'member') THEN
+    v_can_create := TRUE;
+  ELSIF v_member.role = 'contributor' THEN
+    SELECT EXISTS (
+      SELECT 1
+      FROM public.contributor_permissions cp
+      WHERE cp.band_member_id = v_member.id
+        AND cp.can_create_gigs = TRUE
+        AND (
+          cp.can_create_potential_gigs_only = FALSE
+          OR coalesce(p_is_potential, FALSE) = TRUE
+        )
+    )
+    INTO v_can_create;
+  END IF;
+
+  IF NOT v_can_create THEN
+    RAISE EXCEPTION 'Insufficient permissions to create venue for gig save';
+  END IF;
+
+  -- Dedupe by same band + case-insensitive venue name + null-safe city.
+  SELECT v.*
+  INTO v_existing
+  FROM public.venues v
+  WHERE v.band_id = p_band_id
+    AND lower(v.name) = lower(v_name)
+    AND (
+      (v_city IS NULL AND NULLIF(trim(v.city), '') IS NULL)
+      OR (v_city IS NOT NULL AND lower(v.city) = lower(v_city))
+    )
+  ORDER BY v.created_at ASC
+  LIMIT 1;
+
+  IF FOUND THEN
+    RETURN v_existing;
+  END IF;
+
+  INSERT INTO public.venues (band_id, name, city, address, state)
+  VALUES (
+    p_band_id,
+    v_name,
+    v_city,
+    NULLIF(trim(p_address), ''),
+    NULLIF(upper(trim(p_state)), '')
+  )
+  RETURNING * INTO v_created;
+
+  RETURN v_created;
+END;
+$$;
+
+GRANT EXECUTE ON FUNCTION public.create_venue_for_gig_save(UUID, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;
```
