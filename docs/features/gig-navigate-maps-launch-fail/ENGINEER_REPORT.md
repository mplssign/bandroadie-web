# Engineer Report

## Feature Slug

bug/gig-navigate-maps-launch-fail

## Feature Title

Gig Navigate Maps Launch Fail

## Goal

Implement a two-stage gig navigation flow that attempts platform-default launch first, then presents a fallback provider picker (Apple Maps, Google Maps, Waze) only if default launch fails. Restore live reachability to ViewGigDrawer and resolve its missing gig_notes_sheet.dart dependency via the Tony-authorized cherry-pick of commit 38dd08a.

## Architect Tasks Completed

- [x] Task 1 — Updated `ViewGigDrawer` navigate action to attempt platform-resolved default launch URI first.
- [x] Task 2 — Implemented in-app fallback picker with Apple Maps, Google Maps, and Waze options shown only after default-first failure.
- [x] Task 3 — Implemented provider-specific URI builders and launch handlers with per-provider availability/failure messaging.
- [x] Task 4 — Added iOS `LSApplicationQueriesSchemes` entries for `maps`, `comgooglemaps`, and `waze`.
- [x] Task 5 — Added Android `<queries>` entries for `geo`, `google.navigation`, and `waze` schemes because `canLaunchUrl` checks are used.
- [x] Task 6 — Re-ran `flutter analyze` after the Tony-authorized cherry-pick of `38dd08a`; analyzer now passes with 0 errors.

## Files Created

- docs/features/gig-navigate-maps-launch-fail/ENGINEER_REPORT.md
- docs/features/wire-view-gig-drawer-to-gig-tap/ENGINEER_REPORT.md
- lib/features/gigs/widgets/gig_notes_sheet.dart

## Files Modified

- lib/features/calendar/calendar_screen.dart
- lib/features/calendar/calendar_tab_content.dart
- lib/features/gigs/widgets/view_gig_drawer.dart
- lib/features/home/home_screen.dart
- lib/features/home/home_tab_content.dart
- ios/Runner/Info.plist
- android/app/src/main/AndroidManifest.xml

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 0 warnings

## Test Results

Not run (not required by Architect plan).

## Verification

Manual steps performed:

- Confirmed current branch before change: `bug/gig-navigate-maps-launch-fail`.
- Cherry-picked `38dd08a` successfully with no conflicts.
- Verified default-first attempt is executed before picker path in `ViewGigDrawer._openNavigation`.
- Verified picker appears only after default launch fails.
- Verified picker includes Apple Maps, Google Maps, and Waze.
- Verified provider-specific URI paths are used for fallback launches.
- Verified `gig_notes_sheet.dart` now exists and resolves `ViewGigDrawer` import/symbol dependencies.
- Verified Home and Calendar confirmed-gig tap surfaces now route into `ViewGigDrawer` via the cherry-picked wiring.
- Verified `Info.plist` includes required `LSApplicationQueriesSchemes` entries.
- Verified Android manifest includes required map intent queries for package visibility checks.
- Verified final `git diff main` reflects both the maps-launch implementation and the authorized wiring/dependency restoration.

## Deviations From Architect Plan

- Tony authorized an explicit deviation from the Architect plan's original file list: cherry-picked commit `38dd08a` from branch `bug/wire-view-gig-drawer-to-gig-tap`.
- Purpose of deviation: restore live call sites to `ViewGigDrawer` on Home and Calendar, and add the missing `lib/features/gigs/widgets/gig_notes_sheet.dart` dependency required by `view_gig_drawer.dart`.
- Cherry-pick also brought `docs/features/wire-view-gig-drawer-to-gig-tap/ENGINEER_REPORT.md` as part of the original commit payload.

## Blockers Encountered

None.

## Ready For QA

Yes

## Git Diff Main

```diff
diff --git a/android/app/src/main/AndroidManifest.xml b/android/app/src/main/AndroidManifest.xml
index f024a69..1a597bd 100644
--- a/android/app/src/main/AndroidManifest.xml
+++ b/android/app/src/main/AndroidManifest.xml
@@ -95,5 +95,17 @@
		   <action android:name="android.intent.action.PROCESS_TEXT"/>
		   <data android:mimeType="text/plain"/>
	    </intent>
+        <intent>
+            <action android:name="android.intent.action.VIEW"/>
+            <data android:scheme="geo"/>
+        </intent>
+        <intent>
+            <action android:name="android.intent.action.VIEW"/>
+            <data android:scheme="google.navigation"/>
+        </intent>
+        <intent>
+            <action android:name="android.intent.action.VIEW"/>
+            <data android:scheme="waze"/>
+        </intent>
	</queries>
 </manifest>
diff --git a/docs/features/wire-view-gig-drawer-to-gig-tap/ENGINEER_REPORT.md b/docs/features/wire-view-gig-drawer-to-gig-tap/ENGINEER_REPORT.md
new file mode 100644
index 0000000..c545eeb
--- /dev/null
+++ b/docs/features/wire-view-gig-drawer-to-gig-tap/ENGINEER_REPORT.md
@@ -0,0 +1,63 @@
+# Engineer Report
+
+## Feature Slug
+`wire-view-gig-drawer-to-gig-tap`
+
+## Feature Title
+Wire ViewGigDrawer to Gig Tap
+
+## Goal
+`ViewGigDrawer` was fully implemented but had zero call sites. Tapping any confirmed
+gig on Home or Calendar opened `EditGigDrawer` directly, or silently did nothing for
+users without edit permission. This fix wires all four tap surfaces to open
+`ViewGigDrawer` first, with Edit as a secondary action. It also ships `gig_notes_sheet.dart`,
+which `view_gig_drawer.dart` already imports as a compile-time dependency.
+
+## Architect Tasks Completed
+- [x] Task 1 — Create `lib/features/gigs/widgets/gig_notes_sheet.dart` (verbatim copy from `feat/gig-address-field`)
+- [x] Task 2 — Wire `lib/features/home/home_screen.dart` (import, `_openViewGigSheet`, `onTap` change)
+- [x] Task 3 — Wire `lib/features/home/home_tab_content.dart` (import, `_openViewGigSheet`, `onTap` change)
+- [x] Task 4 — Wire `lib/features/calendar/calendar_screen.dart` (import, confirmed-gig branch in `_openEditEventSheet`)
+- [x] Task 5 — Wire `lib/features/calendar/calendar_tab_content.dart` (import, confirmed-gig branch in `_openEditEventSheet`)
+- [x] Task 6 — `flutter analyze` confirmed 0 errors
+
+## Files Created
+- `lib/features/gigs/widgets/gig_notes_sheet.dart`
+
+## Files Modified
+- `lib/features/home/home_screen.dart`
+- `lib/features/home/home_tab_content.dart`
+- `lib/features/calendar/calendar_screen.dart`
+- `lib/features/calendar/calendar_tab_content.dart`
+
+## Analyzer Results
+Command: `flutter analyze`
+Result: 0 errors, 0 warnings
+
+Note: Before this fix, `view_gig_drawer.dart` had an unresolved import (`gig_notes_sheet.dart`
+did not exist on `main`). That pre-existing error is resolved by Task 1 — it was not introduced
+by this implementation.
+
+## Test Results
+Not run — no tests exist that cover these call sites, and the Architect plan did not require
+running `flutter test`.
+
+## Verification
+Manual steps performed:
+- Confirmed `git diff main --stat` shows exactly 4 modified files + 1 new untracked file
+- Confirmed `view_gig_drawer.dart` was not modified (off-limits)
+- Confirmed `financial_entry_repository.dart` was not modified (off-limits)
+- Confirmed `gig.dart` was not modified (off-limits)
+- Confirmed potential gig `onTap` in `home_tab_content.dart` (line 1083, `PotentialGigCard`) was NOT changed — only the confirmed gig `onTap` in `_buildHorizontalGigsList` was updated
+- Confirmed potential gig `onTap` in `home_screen.dart` (line 759, `PotentialGigCard`) was NOT changed
+- `dart format` run on all 5 changed files; formatter made minor whitespace adjustments to the two calendar files; re-ran `flutter analyze` and confirmed still clean
+
+## Deviations From Architect Plan
+None. `onSaved` was intentionally omitted from all `ViewGigDrawer.show()` calls per the
+plan's code review instruction (the parameter is dead code — `ViewGigDrawer` never invokes it).
+
+## Blockers Encountered
+None.
+
+## Ready For QA
+Yes
diff --git a/ios/Runner/Info.plist b/ios/Runner/Info.plist
index e2976e7..adfa368 100644
--- a/ios/Runner/Info.plist
+++ b/ios/Runner/Info.plist
@@ -53,6 +53,12 @@
	<!-- Required -->
	<key>LSRequiresIPhoneOS</key>
	<true/>
+	<key>LSApplicationQueriesSchemes</key>
+	<array>
+		<string>maps</string>
+		<string>comgooglemaps</string>
+		<string>waze</string>
+	</array>

	<!-- Input -->
	<key>UIApplicationSupportsIndirectInputEvents</key>
diff --git a/lib/features/calendar/calendar_screen.dart b/lib/features/calendar/calendar_screen.dart
index a3599d7..b9f7dc6 100644
--- a/lib/features/calendar/calendar_screen.dart
+++ b/lib/features/calendar/calendar_screen.dart
@@ -16,6 +16,7 @@ import '../events/models/event_form_data.dart';
 import '../events/widgets/add_edit_event_bottom_sheet.dart';
 import '../feedback/bug_report_screen.dart';
 import '../gigs/gig_controller.dart';
+import '../gigs/widgets/view_gig_drawer.dart';
 import '../home/widgets/band_switcher.dart';
 import '../home/widgets/side_drawer.dart';
 import '../profile/my_profile_screen.dart';
@@ -236,6 +237,30 @@ class _CalendarScreenState extends ConsumerState<CalendarScreen>
	  loading: () => null,
	  error: (_, __) => null,
	);
+
+    // Confirmed gigs: show read-only view drawer first
+    if (event.isConfirmedGig && event.gig != null) {
+      final bandTimezone = ref.read(activeBandProvider).activeBand?.timezone ??
+          'America/Chicago';
+      final canEdit = editPerms != null && editPerms.canEditGigs;
+      ViewGigDrawer.show(
+        context,
+        gig: event.gig!,
+        bandTimezone: bandTimezone,
+        canEdit: canEdit,
+        onEdit: () => AddEditEventBottomSheet.show(
+          context,
+          ref: ref,
+          mode: EventFormMode.edit,
+          initialType: EventType.gig,
+          existingEventId: event.id,
+          initialData: EventFormData.fromCalendarEvent(event),
+          onSaved: _refreshCalendarData,
+        ),
+      );
+      return;
+    }
+
	// Allow contributors to edit potential gigs they can create
	final canEditEvent = editPerms != null &&
	    (editPerms.canEditGigs ||
diff --git a/lib/features/calendar/calendar_tab_content.dart b/lib/features/calendar/calendar_tab_content.dart
index 01c77d8..7029ec2 100644
--- a/lib/features/calendar/calendar_tab_content.dart
+++ b/lib/features/calendar/calendar_tab_content.dart
@@ -13,6 +13,7 @@ import '../bands/band_full_state.dart';
 import '../events/models/event_form_data.dart';
 import '../events/widgets/add_edit_event_bottom_sheet.dart';
 import '../gigs/gig_controller.dart';
+import '../gigs/widgets/view_gig_drawer.dart';
 import '../members/permissions/band_permissions_provider.dart';
 import '../members/permissions/band_permissions.dart';
 import '../rehearsals/rehearsal_controller.dart';
@@ -218,6 +219,30 @@ class _CalendarTabContentState extends ConsumerState<CalendarTabContent>
	  loading: () => null,
	  error: (_, __) => null,
	);
+
+    // Confirmed gigs: show read-only view drawer first
+    if (event.isConfirmedGig && event.gig != null) {
+      final bandTimezone = ref.read(activeBandProvider).activeBand?.timezone ??
+          'America/Chicago';
+      final canEdit = editPerms != null && editPerms.canEditGigs;
+      ViewGigDrawer.show(
+        context,
+        gig: event.gig!,
+        bandTimezone: bandTimezone,
+        canEdit: canEdit,
+        onEdit: () => AddEditEventBottomSheet.show(
+          context,
+          ref: ref,
+          mode: EventFormMode.edit,
+          initialType: EventType.gig,
+          existingEventId: event.id,
+          initialData: EventFormData.fromCalendarEvent(event),
+          onSaved: _refreshCalendarData,
+        ),
+      );
+      return;
+    }
+
	// Allow contributors to edit potential gigs they can create
	final canEditEvent = editPerms != null &&
	    (editPerms.canEditGigs ||
diff --git a/lib/features/gigs/widgets/gig_notes_sheet.dart b/lib/features/gigs/widgets/gig_notes_sheet.dart
new file mode 100644
index 0000000..e9c55cf
--- /dev/null
+++ b/lib/features/gigs/widgets/gig_notes_sheet.dart
@@ -0,0 +1,114 @@
+import 'package:flutter/material.dart';
+
+import '../../../app/theme/brand_colors.dart';
+import '../../../app/theme/design_tokens.dart';
+import '../../../components/ui/brand_action_button.dart';
+
+class GigNotesSheet extends StatelessWidget {
+  final String notes;
+  final String gigName;
+
+  const GigNotesSheet({
+    super.key,
+    required this.notes,
+    required this.gigName,
+  });
+
+  static void show(
+    BuildContext context, {
+    required String notes,
+    required String gigName,
+  }) {
+    showModalBottomSheet<void>(
+      context: context,
+      isScrollControlled: true,
+      backgroundColor: Colors.transparent,
+      builder: (_) => GigNotesSheet(notes: notes, gigName: gigName),
+    );
+  }
+
+  @override
+  Widget build(BuildContext context) {
+    return Container(
+      constraints: BoxConstraints(
+        maxHeight: MediaQuery.of(context).size.height * 0.8,
+      ),
+      decoration: BoxDecoration(
+        color: context.colors.surface,
+        borderRadius: const BorderRadius.only(
+          topLeft: Radius.circular(20),
+          topRight: Radius.circular(20),
+        ),
+      ),
+      child: Column(
+        mainAxisSize: MainAxisSize.min,
+        crossAxisAlignment: CrossAxisAlignment.start,
+        children: [
+          // Drag handle
+          Center(
+            child: Container(
+              margin: const EdgeInsets.only(top: 12),
+              width: 40,
+              height: 4,
+              decoration: BoxDecoration(
+                color: context.colors.border,
+                borderRadius: BorderRadius.circular(2),
+              ),
+            ),
+          ),
+
+          const SizedBox(height: Spacing.space16),
+
+          // Header
+          Padding(
+            padding: const EdgeInsets.symmetric(
+              horizontal: Spacing.pagePadding,
+            ),
+            child: Text(
+              gigName,
+              style: AppTextStyles.pageTitle.copyWith(
+                color: context.colors.textPrimary,
+              ),
+            ),
+          ),
+
+          const SizedBox(height: Spacing.space16),
+
+          const Divider(height: 1),
+
+          // Notes content — scrollable
+          Flexible(
+            child: SingleChildScrollView(
+              padding: const EdgeInsets.symmetric(
+                horizontal: Spacing.pagePadding,
+                vertical: Spacing.space16,
+              ),
+              child: Text(
+                notes,
+                style: AppTextStyles.callout.copyWith(
+                  color: context.colors.textPrimary,
+                ),
+              ),
+            ),
+          ),
+
+          const SizedBox(height: Spacing.space16),
+
+          // Footer
+          Padding(
+            padding: EdgeInsets.only(
+              left: Spacing.pagePadding,
+              right: Spacing.pagePadding,
+              bottom: MediaQuery.of(context).padding.bottom + Spacing.space16,
+            ),
+            child: BrandActionButton(
+              label: 'Done',
+              fullWidth: true,
+              onPressed: () => Navigator.of(context).pop(),
+            ),
+          ),
+        ],
+      ),
+    );
+  }
+}
diff --git a/lib/features/gigs/widgets/view_gig_drawer.dart b/lib/features/gigs/widgets/view_gig_drawer.dart
index c5acaab..fa0d665 100644
--- a/lib/features/gigs/widgets/view_gig_drawer.dart
+++ b/lib/features/gigs/widgets/view_gig_drawer.dart
@@ -1,4 +1,5 @@
 import 'package:flutter/material.dart';
+import 'package:flutter/foundation.dart';
 import 'package:lucide_flutter/lucide_flutter.dart';
 import 'package:url_launcher/url_launcher.dart';

@@ -52,16 +53,155 @@ class ViewGigDrawer extends StatelessWidget {

   Future<void> _openNavigation(BuildContext context) async {
	final hasAddress = gig.address != null && gig.address!.trim().isNotEmpty;
-    final query = Uri.encodeComponent(
-      hasAddress
-          ? '${gig.address} ${gig.location}'
-          : '${gig.name} ${gig.location}',
+    final query = hasAddress
+        ? '${gig.address} ${gig.location}'
+        : '${gig.name} ${gig.location}';
+
+    final defaultUri = _buildDefaultNavigationUri(query);
+    final openedDefault = await launchUrl(
+      defaultUri,
+      mode: LaunchMode.externalApplication,
+    );
+    if (openedDefault) {
+      return;
+    }
+
+    if (!context.mounted) {
+      return;
+    }
+
+    final provider = await _showNavigationAppPicker(context);
+    if (provider == null) {
+      return;
+    }
+
+    if (!context.mounted) {
+      return;
+    }
+
+    await _launchFallbackProvider(
+      context,
+      provider: provider,
+      query: query,
+    );
+  }
+
+  Uri _buildDefaultNavigationUri(String query) {
+    final encoded = Uri.encodeComponent(query);
+
+    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
+      return Uri.parse('maps://?q=$encoded');
+    }
+
+    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
+      return Uri.parse('geo:0,0?q=$encoded');
+    }
+
+    return Uri.parse('https://maps.google.com/?q=$encoded');
+  }
+
+  Future<_NavigationApp?> _showNavigationAppPicker(BuildContext context) {
+    return showModalBottomSheet<_NavigationApp>(
+      context: context,
+      backgroundColor: context.colors.surface,
+      builder: (sheetContext) {
+        return SafeArea(
+          child: Padding(
+            padding: const EdgeInsets.fromLTRB(
+              Spacing.pagePadding,
+              Spacing.space16,
+              Spacing.pagePadding,
+              Spacing.space16,
+            ),
+            child: Column(
+              mainAxisSize: MainAxisSize.min,
+              crossAxisAlignment: CrossAxisAlignment.start,
+              children: [
+                Text(
+                  'Open with',
+                  style: AppTextStyles.title3.copyWith(
+                    color: context.colors.textPrimary,
+                  ),
+                ),
+                const SizedBox(height: Spacing.space12),
+                ListTile(
+                  contentPadding: EdgeInsets.zero,
+                  title: const Text('Apple Maps'),
+                  onTap: () => Navigator.of(sheetContext).pop(
+                    _NavigationApp.appleMaps,
+                  ),
+                ),
+                ListTile(
+                  contentPadding: EdgeInsets.zero,
+                  title: const Text('Google Maps'),
+                  onTap: () => Navigator.of(sheetContext).pop(
+                    _NavigationApp.googleMaps,
+                  ),
+                ),
+                ListTile(
+                  contentPadding: EdgeInsets.zero,
+                  title: const Text('Waze'),
+                  onTap: () => Navigator.of(sheetContext).pop(
+                    _NavigationApp.waze,
+                  ),
+                ),
+              ],
+            ),
+          ),
+        );
+      },
	);
-    final uri = Uri.parse('https://maps.google.com/?q=$query');
-    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
+  }
+
+  Future<void> _launchFallbackProvider(
+    BuildContext context, {
+    required _NavigationApp provider,
+    required String query,
+  }) async {
+    final appName = _appName(provider);
+    final uri = _providerUri(provider, query);
+
+    final canOpen = await canLaunchUrl(uri);
+    if (!canOpen) {
	  if (context.mounted) {
-        showAppSnackBar(context, message: 'Could not open maps');
+        showAppSnackBar(
+          context,
+          message: '$appName is not available on this device',
+        );
	  }
+      return;
+    }
+
+    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
+    if (!launched && context.mounted) {
+      showAppSnackBar(context, message: 'Could not open $appName');
+    }
+  }
+
+  Uri _providerUri(_NavigationApp app, String query) {
+    final encoded = Uri.encodeComponent(query);
+
+    switch (app) {
+      case _NavigationApp.appleMaps:
+        return Uri.parse('maps://?q=$encoded');
+      case _NavigationApp.googleMaps:
+        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
+          return Uri.parse('comgooglemaps://?q=$encoded');
+        }
+        return Uri.parse('google.navigation:q=$encoded');
+      case _NavigationApp.waze:
+        return Uri.parse('waze://?q=$encoded&navigate=yes');
+    }
+  }
+
+  String _appName(_NavigationApp app) {
+    switch (app) {
+      case _NavigationApp.appleMaps:
+        return 'Apple Maps';
+      case _NavigationApp.googleMaps:
+        return 'Google Maps';
+      case _NavigationApp.waze:
+        return 'Waze';
	}
   }

@@ -293,6 +433,12 @@ class ViewGigDrawer extends StatelessWidget {
   }
 }

+enum _NavigationApp {
+  appleMaps,
+  googleMaps,
+  waze,
+}
+
 class _DetailRow extends StatelessWidget {
   final String label;
   final String value;
diff --git a/lib/features/home/home_screen.dart b/lib/features/home/home_screen.dart
index df89d6e..19ee296 100644
--- a/lib/features/home/home_screen.dart
+++ b/lib/features/home/home_screen.dart
@@ -21,6 +21,7 @@ import '../members/permissions/band_permissions_provider.dart';
 import '../profile/my_profile_screen.dart';
 import '../settings/settings_screen.dart';
 import '../gigs/gig_controller.dart';
+import '../gigs/widgets/view_gig_drawer.dart';
 import '../rehearsals/rehearsal_controller.dart';
 import '../setlists/new_setlist_screen.dart';
 import '../setlists/setlists_screen.dart' show SetlistsState, setlistsProvider;
@@ -238,6 +239,28 @@ class _HomeScreenState extends ConsumerState<HomeScreen>
	);
   }

+  void _openViewGigSheet(Gig gig) {
+    final permsAsync = ref.read(currentUserPermissionsProvider);
+    final perms = permsAsync.when(
+      data: (p) => p,
+      loading: () => null,
+      error: (_, __) => null,
+    );
+    final canEdit = perms != null &&
+        (perms.canEditGigs || (gig.isPotential && perms.canEditPotentialGigs));
+
+    final bandTimezone =
+        ref.read(activeBandProvider).activeBand?.timezone ?? 'America/Chicago';
+
+    ViewGigDrawer.show(
+      context,
+      gig: gig,
+      bandTimezone: bandTimezone,
+      canEdit: canEdit,
+      onEdit: () => _openEditGigSheet(gig),
+    );
+  }
+
   /// Open the Edit Event drawer for an existing rehearsal
   void _openEditRehearsalSheet(Rehearsal rehearsal) {
	// Contributors cannot open the edit drawer
@@ -893,7 +916,7 @@ class _HomeScreenState extends ConsumerState<HomeScreen>
		   gig: gig,
		   bandTimezone: bandTimezone,
		   index: index,
-            onTap: () => _openEditGigSheet(gig),
+            onTap: () => _openViewGigSheet(gig),
		 );
	    },
	  ),
diff --git a/lib/features/home/home_tab_content.dart b/lib/features/home/home_tab_content.dart
index c26df9e..ad748c2 100644
--- a/lib/features/home/home_tab_content.dart
+++ b/lib/features/home/home_tab_content.dart
@@ -19,6 +19,7 @@ import '../events/models/event_form_data.dart';
 import '../events/widgets/add_edit_event_bottom_sheet.dart';
 import '../gigs/gig_controller.dart';
 import '../gigs/gig_response_repository.dart';
+import '../gigs/widgets/view_gig_drawer.dart';
 import '../gigs/potential_gig_prompt_service.dart';
 import '../members/members_controller.dart';
 import '../members/permissions/band_permissions_provider.dart';
@@ -431,6 +432,28 @@ class _HomeTabContentState extends ConsumerState<HomeTabContent>
	);
   }

+  void _openViewGigSheet(Gig gig) {
+    final permsAsync = ref.read(currentUserPermissionsProvider);
+    final perms = permsAsync.when(
+      data: (p) => p,
+      loading: () => null,
+      error: (_, __) => null,
+    );
+    final canEdit = perms != null &&
+        (perms.canEditGigs || (gig.isPotential && perms.canEditPotentialGigs));
+
+    final bandTimezone =
+        ref.read(activeBandProvider).activeBand?.timezone ?? 'America/Chicago';
+
+    ViewGigDrawer.show(
+      context,
+      gig: gig,
+      bandTimezone: bandTimezone,
+      canEdit: canEdit,
+      onEdit: () => _openEditGigSheet(gig),
+    );
+  }
+
   /// Open the Edit Event drawer for an existing rehearsal
   void _openEditRehearsalSheet(Rehearsal rehearsal) {
	// Contributors cannot open the edit drawer
@@ -1158,7 +1181,7 @@ class _HomeTabContentState extends ConsumerState<HomeTabContent>
		   index: index,
		   bandTimezone: ref.watch(activeBandProvider).activeBand?.timezone ??
			  'America/Chicago',
-            onTap: () => _openEditGigSheet(gig),
+            onTap: () => _openViewGigSheet(gig),
		 );
	    },
	  ),
```
