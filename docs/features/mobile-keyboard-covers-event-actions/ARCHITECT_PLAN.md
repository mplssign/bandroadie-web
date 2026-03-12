# ARCHITECT PLAN

Feature Slug
mobile-keyboard-covers-event-actions

Feature Title
Fix mobile keyboard covering event editor actions

---

## Problem

On mobile devices, when editing an event, the on-screen keyboard can cover the bottom action buttons (Save, Cancel, Delete) in the event editor drawer.

Users must manually dismiss the keyboard to access these actions, which breaks the editing flow.

---

## Goal

Ensure event editor actions remain visible when the keyboard is open.

---

## Implementation Strategy

Use keyboard-aware layout behavior so the bottom action row moves above the keyboard.

Approach:

• Apply bottom padding using `MediaQuery.viewInsets.bottom`
• Ensure the event editor body scrolls when the keyboard opens
• Keep the action row pinned above the keyboard
• Preserve the existing 90% drawer height constraint

---

## Files Expected To Change

lib/features/events/widgets/event_editor_drawer.dart

Potential component updates:

lib/features/events/widgets/event_editor_actions.dart

---

## Acceptance Criteria

• Keyboard never covers Save / Cancel / Delete
• Works on iOS and Android
• Drawer height remains stable
• Scroll behavior remains smooth
