# Engineer Report

## Feature Slug

bug/pre-deploy-logging-cleanup

## Feature Title

Remove production logging before deploy

## Goal

Eliminate all production logging statements (`print()` and `// ignore: avoid_print` suppressions) from the codebase to prevent sensitive data exposure in production builds. Replace debug-critical logs with `debugPrint()` guarded by `kDebugMode` checks.

## Architect Tasks Completed

- [x] Task 1 — Add `import 'package:flutter/foundation.dart'` to all three modified files
- [x] Task 2 — Replace all `print()` calls with `debugPrint()` wrapped in `if (kDebugMode)` blocks
- [x] Task 3 — Remove all `// ignore: avoid_print` lint suppressions
- [x] Task 4 — Remove error details and stack traces from debug statements
- [x] Task 5 — Remove verbose logging statements from repositories
- [x] Task 6 — Run `dart format` on modified files
- [x] Task 7 — Run `flutter analyze` to confirm no errors
- [x] Task 8 — Search for remaining `print()` calls in scoped files
- [x] Task 9 — Search for remaining `// ignore: avoid_print` comments in scoped files

## Files Created

- `docs/features/pre-deploy-logging-cleanup/ENGINEER_REPORT.md`

## Files Modified

- `lib/features/financials/financials_controller.dart`
- `lib/features/members/members_repository.dart`
- `lib/features/profile/user_band_roles_repository.dart`
- `pubspec.yaml`

## Analyzer Results

Command: `flutter analyze`
Result: No issues found!

All files pass static analysis with zero errors and zero warnings.

## Test Results

Not run — no test suite exists for these files. Manual verification performed via code review and analyzer.

## Verification

Manual steps performed:

- **Code formatting**: Ran `dart format` on all three modified files — formatting already correct
- **Static analysis**: Ran `flutter analyze` — 0 errors, 0 warnings
- **Print statement audit**: Searched for `print(` in all three files — only `debugPrint()` calls remain, all wrapped in `kDebugMode` guards
- **Lint suppression audit**: Searched for `// ignore: avoid_print` in all three files — zero matches, all suppressions removed
- **Import verification**: Confirmed `package:flutter/foundation.dart` imported in all three files for `kDebugMode` and `debugPrint` access

### Changes Summary

**pubspec.yaml:**

- Version bump: `1.2.21+176` → `1.2.22+177`

**financials_controller.dart:**

- Added `import 'package:flutter/foundation.dart'`
- Replaced production `print()` calls with `debugPrint()` in `kDebugMode` blocks
- Removed all scoped `// ignore: avoid_print` comments
- Removed stack trace logging from error handlers (`catch (e, st)` → `catch (e)`)
- Simplified error messages (removed `$e\n$st` interpolation)

**members_repository.dart:**

- Added `import 'package:flutter/foundation.dart'`
- Removed all scoped production `print()` statements (cache hits, query logging, user ID lookups)
- Removed all scoped `// ignore: avoid_print` comments
- Replaced remaining debug statements with `debugPrint()` in `kDebugMode` blocks
- Simplified error messages

**user_band_roles_repository.dart:**

- Added `import 'package:flutter/foundation.dart'`
- Replaced production `print()` calls with `debugPrint()` in `kDebugMode` blocks
- Removed all scoped `// ignore: avoid_print` comments
- Removed error details from debug statements (stripped `$e` interpolation)

## Deviations From Architect Plan

None — all production logging removed as specified. Error handlers in `financials_controller.dart` retain `rethrow` behavior to preserve error propagation while eliminating verbose console output.

## Blockers Encountered

None

## Ready For QA

Yes — All production logging eliminated, analyzer passes cleanly, no runtime behavior changes (errors still propagate correctly).

---

## Git Diff Output

```diff
diff --git a/lib/features/financials/financials_controller.dart b/lib/features/financials/financials_controller.dart
index fdb16b0..8f44d9a 100644
--- a/lib/features/financials/financials_controller.dart
+++ b/lib/features/financials/financials_controller.dart
@@ -1,3 +1,4 @@
+import 'package:flutter/foundation.dart';
 import 'package:flutter_riverpod/flutter_riverpod.dart';

 import '../bands/active_band_controller.dart';
@@ -179,9 +180,10 @@ class FinancialsNotifier extends Notifier<FinancialsState> {
       state = state.copyWith(
         allEntries: [entry, ...state.allEntries],
       );
-    } catch (e, st) {
-      // ignore: avoid_print
-      print('addEntry failed: $e\n$st');
+    } catch (e) {
+      if (kDebugMode) {
+        debugPrint('addEntry failed');
+      }
       rethrow;
     }
   }
@@ -226,9 +228,10 @@ class FinancialsNotifier extends Notifier<FinancialsState> {
         allEntries:
             state.allEntries.map((e) => e.id == entryId ? updated : e).toList(),
       );
-    } catch (e, st) {
-      // ignore: avoid_print
-      print('updateEntry failed: $e\n$st');
+    } catch (e) {
+      if (kDebugMode) {
+        debugPrint('updateEntry failed');
+      }
       rethrow;
     }
   }
diff --git a/lib/features/members/members_repository.dart b/lib/features/members/members_repository.dart
index c996219..528b534 100644
--- a/lib/features/members/members_repository.dart
+++ b/lib/features/members/members_repository.dart
@@ -1,3 +1,4 @@
+import 'package:flutter/foundation.dart';
 import 'package:flutter_riverpod/flutter_riverpod.dart';

 import 'package:bandroadie/app/services/supabase_client.dart';
@@ -98,17 +99,10 @@ class MembersRepository {
     if (!forceRefresh) {
       final cached = _cache[bandId];
       if (cached != null && !cached.isExpired) {
-        // ignore: avoid_print
-        print(
-          '[MembersRepository] Returning cached: ${cached.data.members.length} members, ${cached.data.pendingInvites.length} invites',
-        );
         return cached.data;
       }
     }

-    // ignore: avoid_print
-    print('[MembersRepository] Fetching members for band: $bandId');
-
     // =========================================
     // QUERY A: band_members
     // Only include 'active' or 'invited' status members
@@ -121,10 +115,6 @@ class MembersRepository {
             ascending: true);

     final bandMemberRows = List<Map<String, dynamic>>.from(bandMembersResponse);
-    // ignore: avoid_print
-    print(
-      '[MembersRepository] Query A: ${bandMemberRows.length} band_members rows',
-    );

     // Collect user IDs for the profile query
     final userIds = bandMemberRows
@@ -140,11 +130,6 @@ class MembersRepository {
     Map<String, Map<String, dynamic>> usersById = {};

     if (userIds.isNotEmpty) {
-      // ignore: avoid_print
-      print(
-        '[MembersRepository] Query B: looking up ${userIds.length} userIds: ${userIds.take(3).toList()}',
-      );
-
       final usersResponse = await supabase
           .from('users')
           .select(
@@ -153,46 +138,24 @@ class MembersRepository {
           .inFilter('id', userIds);

       final userRows = List<Map<String, dynamic>>.from(usersResponse);
-      // ignore: avoid_print
-      print('[MembersRepository] Query B: ${userRows.length} users returned');

-      // Build lookup map and log first few (sanitized - no full emails)
-      for (int i = 0; i < userRows.length; i++) {
-        final user = userRows[i];
+      // Build lookup map
+      for (final user in userRows) {
         final id = user['id'] as String?;
         if (id != null) {
           usersById[id] = user;
-          if (i < 3) {
-            final firstName = user['first_name'] as String? ?? '';
-            final lastName = user['last_name'] as String? ?? '';
-            final hasEmail = (user['email'] as String?)?.isNotEmpty ?? false;
-            // ignore: avoid_print
-            print(
-              '[MembersRepository]   user[$i]: id=${id.substring(0, 8)}... name="$firstName $lastName" hasEmail=$hasEmail',
-            );
-          }
         }
       }
     }

-    // Debug: log missing users count and which IDs are missing
-    final missingUsersCount = userIds.length - usersById.length;
-    if (missingUsersCount > 0) {
-      // ignore: avoid_print
-      print(
-        '[MembersRepository] ⚠️ Missing users: $missingUsersCount/${userIds.length}',
-      );
-      // Log which user IDs are missing (truncated for privacy)
-      final missingIds =
-          userIds.where((id) => !usersById.containsKey(id)).toList();
-      // ignore: avoid_print
-      print(
-        '[MembersRepository]   Missing user ID prefixes: ${missingIds.take(5).map((id) => id.substring(0, 8)).toList()}',
-      );
-      // ignore: avoid_print
-      print(
-        '[MembersRepository]   Likely cause: RLS policy blocking bandmate reads. Run migration 056_users_rls_band_members.sql',
-      );
+    // Debug: check for missing users in debug mode only
+    if (kDebugMode) {
+      final missingUsersCount = userIds.length - usersById.length;
+      if (missingUsersCount > 0) {
+        debugPrint(
+          '[MembersRepository] ⚠️ Missing $missingUsersCount users. Likely RLS issue.',
+        );
+      }
     }

     // =========================================
@@ -206,10 +169,6 @@ class MembersRepository {
         .order('created_at', ascending: false);

     final inviteRows = List<Map<String, dynamic>>.from(invitesResponse);
-    // ignore: avoid_print
-    print(
-      '[MembersRepository] Query C: ${inviteRows.length} pending invitations',
-    );

     // =========================================
     // QUERY D: user_band_roles (band-specific roles)
@@ -222,14 +181,11 @@ class MembersRepository {
           bandId: bandId,
           userIds: userIds,
         );
-        // ignore: avoid_print
-        print(
-          '[MembersRepository] Query D: ${bandSpecificRoles.length} users have band-specific roles',
-        );
       } catch (e) {
         // If query fails, just use empty map (fall back to global roles)
-        // ignore: avoid_print
-        print('[MembersRepository] Query D failed (using global roles): $e');
+        if (kDebugMode) {
+          debugPrint('[MembersRepository] Query D failed (using global roles)');
+        }
       }
     }

@@ -237,17 +193,12 @@ class MembersRepository {
     // MERGE: Combine band_members + users + band_roles
     // =========================================
     final members = <MemberVM>[];
-    int resolvedCount = 0;

     for (final memberRow in bandMemberRows) {
       try {
         final odaId = memberRow['user_id'] as String;
         final userRow = usersById[odaId]; // May be null

-        if (userRow != null) {
-          resolvedCount++;
-        }
-
         // Check if this user has band-specific roles
         final bandRolesOverride = bandSpecificRoles[odaId];

@@ -260,17 +211,13 @@ class MembersRepository {
           ),
         );
       } catch (e) {
-        // Skip malformed rows but log the error
-        // ignore: avoid_print
-        print('[MembersRepository] Failed to parse member: $e');
+        // Skip malformed rows but log the error in debug mode
+        if (kDebugMode) {
+          debugPrint('[MembersRepository] Failed to parse member');
+        }
       }
     }

-    // ignore: avoid_print
-    print(
-      '[MembersRepository] Merged: $resolvedCount/${bandMemberRows.length} members have user rows',
-    );
-
     // =========================================
     // SORT: Alphabetically by last name, then first name
     // =========================================
@@ -295,16 +242,13 @@ class MembersRepository {
       try {
         pendingInvites.add(PendingInviteVM.fromJson(inviteRow));
       } catch (e) {
-        // ignore: avoid_print
-        print('[MembersRepository] Failed to parse invite: $e');
+        // Skip malformed rows
+        if (kDebugMode) {
+          debugPrint('[MembersRepository] Failed to parse invite');
+        }
       }
     }

-    // ignore: avoid_print
-    print(
-      '[MembersRepository] Final: ${members.length} members, ${pendingInvites.length} pending invites',
-    );
-
     final result = MembersData(
       members: members,
       pendingInvites: pendingInvites,
@@ -353,8 +297,9 @@ class MembersRepository {

       return true;
     } catch (e) {
-      // ignore: avoid_print
-      print('[MembersRepository] Failed to remove member: $e');
+      if (kDebugMode) {
+        debugPrint('[MembersRepository] Failed to remove member');
+      }
       rethrow;
     }
   }
@@ -377,8 +322,10 @@ class MembersRepository {
       if (response == null) return null;
       return ContributorPermissions.fromJson(response);
     } catch (e) {
-      // ignore: avoid_print
-      print('[MembersRepository] Failed to fetch contributor permissions: $e');
+      if (kDebugMode) {
+        debugPrint(
+            '[MembersRepository] Failed to fetch contributor permissions');
+      }
       rethrow;
     }
   }
@@ -419,8 +366,9 @@ class MembersRepository {

       return true;
     } catch (e) {
-      // ignore: avoid_print
-      print('[MembersRepository] Failed to update member role: $e');
+      if (kDebugMode) {
+        debugPrint('[MembersRepository] Failed to update member role');
+      }
       rethrow;
     }
   }
diff --git a/lib/features/profile/user_band_roles_repository.dart b/lib/features/profile/user_band_roles_repository.dart
index 102ac2b..9a21916 100644
--- a/lib/features/profile/user_band_roles_repository.dart
+++ b/lib/features/profile/user_band_roles_repository.dart
@@ -1,3 +1,4 @@
+import 'package:flutter/foundation.dart';
 import 'package:flutter_riverpod/flutter_riverpod.dart';

 import 'package:bandroadie/app/services/supabase_client.dart';
@@ -100,8 +101,9 @@ class UserBandRolesRepository {
       return roles;
     } catch (e) {
       // On error, don't cache — rethrow so caller can handle
-      // ignore: avoid_print
-      print('[UserBandRolesRepository] Error fetching roles: $e');
+      if (kDebugMode) {
+        debugPrint('[UserBandRolesRepository] Error fetching roles');
+      }
       rethrow;
     }
   }
@@ -174,8 +176,9 @@ class UserBandRolesRepository {

       return result;
     } catch (e) {
-      // ignore: avoid_print
-      print('[UserBandRolesRepository] Error batch fetching roles: $e');
+      if (kDebugMode) {
+        debugPrint('[UserBandRolesRepository] Error batch fetching roles');
+      }
       rethrow;
     }
   }
@@ -218,8 +221,9 @@ class UserBandRolesRepository {

       return result;
     } catch (e) {
-      // ignore: avoid_print
-      print('[UserBandRolesRepository] Error fetching roles for users: $e');
+      if (kDebugMode) {
+        debugPrint('[UserBandRolesRepository] Error fetching roles for users');
+      }
       rethrow;
     }
   }
diff --git a/pubspec.yaml b/pubspec.yaml
index 003a172..fbdb818 100644
--- a/pubspec.yaml
+++ b/pubspec.yaml
@@ -2,7 +2,7 @@ name: bandroadie
 description: "Gig and setlist management for bands."
 publish_to: "none"

-version: 1.2.21+176
+version: 1.2.22+177

 environment:
   sdk: ">=3.3.0 <4.0.0"
```
