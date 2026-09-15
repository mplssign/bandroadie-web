## Summary

Shared confirmation dialogs rendered their title, message, and actions against the Forui dialog card edges because the shared builder supplied no inner content padding.

## Changes

- Add the standard 24px design-token inset around shared Forui confirmation-dialog content.
- Preserve existing wording, callbacks, action alignment, and destructive button styling.
- Add widget regression coverage for the content-padding contract.

There are no migrations, RLS, RPC, schema, dependency, configuration, or routing changes.

## Verification

- `flutter analyze` - no issues.
- Focused dialog tests - 8 passed.
- Full Flutter test suite - 322 passed.
- Affected members and calendar spot tests - 4 passed.
- Independent QA reviewed the code paths and returned `APPROVED`.

## Manual Verification Punch List

**Setup:** Install the PR build on the real iPhone where the original issue was observed. Sign in, switch to a band where you are an admin, and ensure the band has one pending invite, one removable non-admin test member, and one disposable saved venue.

1. Open **Invite Members** and locate the pending invitation row. **Expected:** The row displays its Cancel-invite affordance.
2. Tap the Cancel-invite affordance. **Expected:** A dialog appears titled **Cancel Invite?**, with body **Cancel invite for `<email>`?** and actions **Cancel** and **Cancel Invite**.
3. Inspect the Cancel Invite dialog without dismissing it. **Expected:** Title and body are inset about 24px from the card edges; the rightmost action has clear space from the bottom-right corner; no text is clipped or flush against the border.
4. Tap **Cancel**, reopen the dialog, then tap **Cancel Invite**. **Expected:** Cancel causes no side effect. Cancel Invite removes the invitation and refreshes the pending-invite list.
5. Open **Member management**, open a non-admin test member's edit drawer, and tap **Remove from band**. **Expected:** A **Remove `<Name>`?** dialog appears with the planned body and **Cancel** and red/destructive **Remove** actions.
6. Inspect the Remove Member dialog. **Expected:** The same approximately 24px card-inner inset is visible on all sides; the Remove button remains red and is not flush with the card edge.
7. Tap **Cancel**, reopen the dialog, then tap **Remove** for the disposable member. **Expected:** Cancel causes no removal. Remove succeeds and the drawer/list updates as before.
8. Open **Venue management**, open a disposable saved venue, and tap **Delete Venue**. **Expected:** A **Delete Venue?** dialog appears with body **This action cannot be undone.** and **Cancel** and red/destructive **Delete** actions.
9. Inspect the Delete Venue dialog. **Expected:** The same approximately 24px card-inner inset is visible; the Delete button remains red and inset; no text or action is clipped.
10. Tap **Cancel**, reopen the dialog, then tap **Delete**. **Expected:** Cancel causes no deletion. Delete removes the disposable venue as before.
11. Open **Delete Contact**, **Delete Custom Role**, and **Delete Block Out** confirmation dialogs. **Expected:** Each shared alert dialog has the same comfortable padding, preserved labels/variants, and no clipping or cramped edge collision.
12. On macOS or Chrome, open any one shared alert dialog at a normal window width and then near the dialog's practical minimum width. **Expected:** The same inner padding applies, actions retain their semantics and styling, and content remains unclipped within Forui's 280-560px dialog constraints.

Any deviation in padding, clipping, action result, or destructive styling is a blocker and should be returned with the affected step number.