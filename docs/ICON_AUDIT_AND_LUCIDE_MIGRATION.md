# BandRoadie Icon Audit & Lucide Migration Plan

**Date:** 2025-03-12
**Scope:** Full codebase — Flutter (iOS, Android, macOS, Web), marketing landing page, shared components, SVG assets

---

## Icon Inventory Table

### Authentication

| File                                       | Screen/Component | Current Icon                  | Library  | Purpose                   | Lucide Replacement | Lucide URL                            | Confidence |
| ------------------------------------------ | ---------------- | ----------------------------- | -------- | ------------------------- | ------------------ | ------------------------------------- | ---------- |
| lib/features/auth/auth_confirm_screen.dart | Auth Confirm     | `Icons.browser_not_supported` | Material | Unsupported browser error | `globe`            | https://lucide.dev/icons/globe        | Medium     |
| lib/features/auth/auth_confirm_screen.dart | Auth Confirm     | `Icons.refresh`               | Material | Retry/refresh action      | `refresh-cw`       | https://lucide.dev/icons/refresh-cw   | High       |
| lib/features/auth/auth_confirm_screen.dart | Auth Confirm     | `Icons.timer_off`             | Material | Token expired             | `timer-off`        | https://lucide.dev/icons/timer-off    | High       |
| lib/features/auth/auth_confirm_screen.dart | Auth Confirm     | `Icons.link_off`              | Material | Invalid link              | `link-2-off`       | https://lucide.dev/icons/link-2-off   | High       |
| lib/features/auth/auth_confirm_screen.dart | Auth Confirm     | `Icons.person_off`            | Material | User not found            | `user-x`           | https://lucide.dev/icons/user-x       | High       |
| lib/features/auth/auth_confirm_screen.dart | Auth Confirm     | `Icons.error_outline`         | Material | Generic error             | `circle-alert`     | https://lucide.dev/icons/circle-alert | High       |
| lib/features/auth/auth_confirm_screen.dart | Auth Confirm     | `Icons.email`                 | Material | Email icon                | `mail`             | https://lucide.dev/icons/mail         | High       |
| lib/features/auth/auth_gate.dart           | Auth Gate        | `Icons.check_circle`          | Material | Success indicator         | `circle-check`     | https://lucide.dev/icons/circle-check | High       |
| lib/features/auth/auth_gate.dart           | Auth Gate        | `Icons.close`                 | Material | Dismiss/close             | `x`                | https://lucide.dev/icons/x            | High       |
| lib/features/auth/invite_screen.dart       | Invite Screen    | `Icons.error_outline`         | Material | Error state               | `circle-alert`     | https://lucide.dev/icons/circle-alert | High       |
| lib/features/auth/invite_screen.dart       | Invite Screen    | `Icons.check_circle`          | Material | Invite accepted           | `circle-check`     | https://lucide.dev/icons/circle-check | High       |
| lib/features/auth/invite_screen.dart       | Invite Screen    | `Icons.email_outlined`        | Material | Email field icon          | `mail`             | https://lucide.dev/icons/mail         | High       |
| lib/features/auth/invite_screen.dart       | Invite Screen    | `Icons.group_add`             | Material | Add to group/invite       | `user-plus`        | https://lucide.dev/icons/user-plus    | High       |

### Navigation & Bottom Nav Bar

| File                                                   | Screen/Component | Current Icon                   | Library  | Purpose       | Lucide Replacement | Lucide URL                          | Confidence |
| ------------------------------------------------------ | ---------------- | ------------------------------ | -------- | ------------- | ------------------ | ----------------------------------- | ---------- |
| lib/features/home/widgets/animated_bottom_nav_bar.dart | Bottom Nav       | `Icons.home_rounded`           | Material | Dashboard tab | `house`            | https://lucide.dev/icons/house      | High       |
| lib/features/home/widgets/animated_bottom_nav_bar.dart | Bottom Nav       | `Icons.queue_music_rounded`    | Material | Setlists tab  | `list-music`       | https://lucide.dev/icons/list-music | High       |
| lib/features/home/widgets/animated_bottom_nav_bar.dart | Bottom Nav       | `Icons.calendar_today_rounded` | Material | Calendar tab  | `calendar`         | https://lucide.dev/icons/calendar   | High       |
| lib/features/home/widgets/animated_bottom_nav_bar.dart | Bottom Nav       | `Icons.people_rounded`         | Material | Members tab   | `users`            | https://lucide.dev/icons/users      | High       |

### Home & Dashboard

| File                                              | Screen/Component   | Current Icon                  | Library  | Purpose                | Lucide Replacement | Lucide URL                          | Confidence |
| ------------------------------------------------- | ------------------ | ----------------------------- | -------- | ---------------------- | ------------------ | ----------------------------------- | ---------- |
| lib/features/home/home_screen.dart                | Home Screen        | `Icons.music_off_rounded`     | Material | Empty state (no songs) | `music-off`        | https://lucide.dev/icons/music-off  | High       |
| lib/features/home/home_screen.dart                | Home Screen        | `Icons.refresh_rounded`       | Material | Refresh data           | `refresh-cw`       | https://lucide.dev/icons/refresh-cw | High       |
| lib/features/home/home_tab_content.dart           | Home Tab           | `Icons.music_off_rounded`     | Material | Empty state (no songs) | `music-off`        | https://lucide.dev/icons/music-off  | High       |
| lib/features/home/home_tab_content.dart           | Home Tab           | `Icons.refresh_rounded`       | Material | Refresh data           | `refresh-cw`       | https://lucide.dev/icons/refresh-cw | High       |
| lib/features/home/widgets/home_app_bar.dart       | Home App Bar       | `Icons.menu_rounded`          | Material | Open drawer/menu       | `menu`             | https://lucide.dev/icons/menu       | High       |
| lib/features/home/widgets/no_band_state.dart      | No Band State      | `Icons.music_note_rounded`    | Material | Music empty state      | `music`            | https://lucide.dev/icons/music      | High       |
| lib/features/home/widgets/no_band_state.dart      | No Band State      | `Icons.add_rounded`           | Material | Add/create band        | `plus`             | https://lucide.dev/icons/plus       | High       |
| lib/features/home/widgets/empty_home_state.dart   | Empty Home         | `Icons.rocket_launch_rounded` | Material | Getting started/launch | `rocket`           | https://lucide.dev/icons/rocket     | High       |
| lib/features/home/widgets/empty_section_card.dart | Empty Section Card | `Icons.add_rounded`           | Material | Add item CTA           | `plus`             | https://lucide.dev/icons/plus       | High       |
| lib/features/home/widgets/band_switcher.dart      | Band Switcher      | `Icons.close_rounded`         | Material | Close overlay          | `x`                | https://lucide.dev/icons/x          | High       |
| lib/features/home/widgets/rehearsal_card.dart     | Rehearsal Card     | `Icons.location_on`           | Material | Venue/location         | `map-pin`          | https://lucide.dev/icons/map-pin    | High       |

### Side Drawer & Settings Navigation

| File                                       | Screen/Component | Current Icon                      | Library  | Purpose             | Lucide Replacement | Lucide URL                         | Confidence |
| ------------------------------------------ | ---------------- | --------------------------------- | -------- | ------------------- | ------------------ | ---------------------------------- | ---------- |
| lib/features/home/widgets/side_drawer.dart | Side Drawer      | `Icons.person_outline_rounded`    | Material | Profile link        | `user`             | https://lucide.dev/icons/user      | High       |
| lib/features/home/widgets/side_drawer.dart | Side Drawer      | `Icons.settings_outlined`         | Material | Settings link       | `settings`         | https://lucide.dev/icons/settings  | High       |
| lib/features/home/widgets/side_drawer.dart | Side Drawer      | `Icons.lightbulb_outline_rounded` | Material | Tips & tricks       | `lightbulb`        | https://lucide.dev/icons/lightbulb | High       |
| lib/features/home/widgets/side_drawer.dart | Side Drawer      | `Icons.bug_report_outlined`       | Material | Bug report/feedback | `bug`              | https://lucide.dev/icons/bug       | High       |
| lib/features/home/widgets/side_drawer.dart | Side Drawer      | `Icons.logout_rounded`            | Material | Logout action       | `log-out`          | https://lucide.dev/icons/log-out   | High       |
| lib/features/home/widgets/side_drawer.dart | Side Drawer      | `Icons.close_rounded`             | Material | Close drawer        | `x`                | https://lucide.dev/icons/x         | High       |
| lib/main.dart                              | App Root         | `Icons.settings_outlined`         | Material | Settings (fallback) | `settings`         | https://lucide.dev/icons/settings  | High       |

### Calendar & Events

| File                                                            | Screen/Component | Current Icon                    | Library  | Purpose                  | Lucide Replacement | Lucide URL                                                     | Confidence |
| --------------------------------------------------------------- | ---------------- | ------------------------------- | -------- | ------------------------ | ------------------ | -------------------------------------------------------------- | ---------- |
| lib/features/calendar/calendar_screen.dart                      | Calendar Screen  | `Icons.error_outline_rounded`   | Material | Error state              | `circle-alert`     | https://lucide.dev/icons/circle-alert                          | High       |
| lib/features/calendar/calendar_screen.dart                      | Calendar Screen  | `Icons.add_rounded`             | Material | Add event                | `plus`             | https://lucide.dev/icons/plus                                  | High       |
| lib/features/calendar/calendar_screen.dart                      | Calendar Screen  | `Icons.event_available_rounded` | Material | Event confirmed          | `calendar-check`   | https://lucide.dev/icons/calendar-check                        | High       |
| lib/features/calendar/calendar_tab_content.dart                 | Calendar Tab     | `Icons.add_rounded`             | Material | Add event                | `plus`             | https://lucide.dev/icons/plus                                  | High       |
| lib/features/calendar/calendar_tab_content.dart                 | Calendar Tab     | `Icons.error_outline_rounded`   | Material | Error state              | `circle-alert`     | https://lucide.dev/icons/circle-alert                          | High       |
| lib/features/calendar/calendar_tab_content.dart                 | Calendar Tab     | `Icons.event_available_rounded` | Material | Event confirmed          | `calendar-check`   | https://lucide.dev/icons/calendar-check                        | High       |
| lib/features/calendar/widgets/calendar_app_bar.dart             | Calendar App Bar | `Icons.menu_rounded`            | Material | Open drawer              | `menu`             | https://lucide.dev/icons/menu                                  | High       |
| lib/features/calendar/widgets/calendar_event_card.dart          | Event Card       | `Icons.chevron_right_rounded`   | Material | Navigate to detail       | `chevron-right`    | https://lucide.dev/icons/chevron-right                         | High       |
| lib/features/calendar/widgets/calendar_grid.dart                | Calendar Grid    | `Icons.chevron_left_rounded`    | Material | Previous month           | `chevron-left`     | https://lucide.dev/icons/chevron-left                          | High       |
| lib/features/calendar/widgets/calendar_grid.dart                | Calendar Grid    | `Icons.chevron_right_rounded`   | Material | Next month               | `chevron-right`    | https://lucide.dev/icons/chevron-right                         | High       |
| lib/features/calendar/widgets/calendar_subscription_dialog.dart | Cal Subscribe    | `Icons.error_outline`           | Material | Error state              | `circle-alert`     | https://lucide.dev/icons/circle-alert                          | High       |
| lib/features/calendar/widgets/calendar_subscription_dialog.dart | Cal Subscribe    | `Icons.calendar_month`          | Material | Calendar subscription    | `calendar`         | https://lucide.dev/icons/calendar                              | High       |
| lib/features/calendar/widgets/calendar_subscription_dialog.dart | Cal Subscribe    | `Icons.close`                   | Material | Close dialog             | `x`                | https://lucide.dev/icons/x                                     | High       |
| lib/features/calendar/widgets/calendar_subscription_dialog.dart | Cal Subscribe    | `Icons.apple`                   | Material | Apple Calendar           | `apple`            | https://lucide.dev/icons/apple                                 | High       |
| lib/features/calendar/widgets/calendar_subscription_dialog.dart | Cal Subscribe    | `Icons.event`                   | Material | Google Calendar          | `calendar-days`    | https://lucide.dev/icons/calendar-days                         | High       |
| lib/features/calendar/widgets/calendar_subscription_dialog.dart | Cal Subscribe    | `Icons.mail_outline`            | Material | Email calendar sync      | `mail`             | https://lucide.dev/icons/mail                                  | High       |
| lib/features/calendar/widgets/calendar_subscription_dialog.dart | Cal Subscribe    | `Icons.check` / `Icons.copy`    | Material | Copy-to-clipboard toggle | `check` / `copy`   | https://lucide.dev/icons/check / https://lucide.dev/icons/copy | High       |
| lib/features/calendar/widgets/day_detail_bottom_sheet.dart      | Day Detail Sheet | `Icons.close_rounded`           | Material | Close sheet              | `x`                | https://lucide.dev/icons/x                                     | High       |
| lib/features/calendar/widgets/day_detail_bottom_sheet.dart      | Day Detail Sheet | `Icons.add_rounded`             | Material | Add event to day         | `plus`             | https://lucide.dev/icons/plus                                  | High       |
| lib/features/calendar/widgets/add_block_out_drawer.dart         | Block Out Drawer | `Icons.close_rounded`           | Material | Close drawer             | `x`                | https://lucide.dev/icons/x                                     | High       |
| lib/features/calendar/widgets/add_block_out_drawer.dart         | Block Out Drawer | `Icons.info_outline_rounded`    | Material | Info tooltip             | `info`             | https://lucide.dev/icons/info                                  | High       |
| lib/features/calendar/widgets/add_block_out_drawer.dart         | Block Out Drawer | `Icons.error_outline_rounded`   | Material | Validation error         | `circle-alert`     | https://lucide.dev/icons/circle-alert                          | High       |
| lib/features/calendar/widgets/add_block_out_drawer.dart         | Block Out Drawer | `Icons.calendar_today_rounded`  | Material | Date picker trigger      | `calendar`         | https://lucide.dev/icons/calendar                              | High       |

### Gigs & Availability

| File                                                     | Screen/Component   | Current Icon            | Library  | Purpose                 | Lucide Replacement | Lucide URL                              | Confidence |
| -------------------------------------------------------- | ------------------ | ----------------------- | -------- | ----------------------- | ------------------ | --------------------------------------- | ---------- |
| lib/features/gigs/widgets/availability_prompt_modal.dart | Availability Modal | `Icons.event_available` | Material | Availability check      | `calendar-check`   | https://lucide.dev/icons/calendar-check | High       |
| lib/features/gigs/widgets/availability_prompt_modal.dart | Availability Modal | `Icons.calendar_today`  | Material | Confirm attendance date | `calendar`         | https://lucide.dev/icons/calendar       | High       |
| lib/features/gigs/widgets/availability_prompt_modal.dart | Availability Modal | `Icons.access_time`     | Material | Time indicator          | `clock`            | https://lucide.dev/icons/clock          | High       |
| lib/features/gigs/widgets/availability_prompt_modal.dart | Availability Modal | `Icons.location_on`     | Material | Venue location          | `map-pin`          | https://lucide.dev/icons/map-pin        | High       |
| lib/features/gigs/widgets/availability_prompt_modal.dart | Availability Modal | `Icons.close`           | Material | Close/decline           | `x`                | https://lucide.dev/icons/x              | High       |
| lib/features/gigs/widgets/availability_prompt_modal.dart | Availability Modal | `Icons.check`           | Material | Confirm/accept          | `check`            | https://lucide.dev/icons/check          | High       |

### Events & Form Fields

| File                                                   | Screen/Component     | Current Icon                        | Library  | Purpose            | Lucide Replacement | Lucide URL                             | Confidence |
| ------------------------------------------------------ | -------------------- | ----------------------------------- | -------- | ------------------ | ------------------ | -------------------------------------- | ---------- |
| lib/features/events/widgets/rehearsal_form_fields.dart | Rehearsal Form       | `Icons.event_rounded`               | Material | Rehearsal label    | `calendar-days`    | https://lucide.dev/icons/calendar-days | High       |
| lib/features/events/widgets/rehearsal_form_fields.dart | Rehearsal Form       | `Icons.close_rounded`               | Material | Remove rehearsal   | `x`                | https://lucide.dev/icons/x             | High       |
| lib/features/events/widgets/event_form_fields.dart     | Event Form           | `Icons.error_outline_rounded`       | Material | Validation error   | `circle-alert`     | https://lucide.dev/icons/circle-alert  | High       |
| lib/features/events/widgets/event_form_fields.dart     | Event Form           | `Icons.add_rounded`                 | Material | Add item           | `plus`             | https://lucide.dev/icons/plus          | High       |
| lib/features/events/widgets/event_form_fields.dart     | Event Form           | `Icons.calendar_today_rounded`      | Material | Date picker        | `calendar`         | https://lucide.dev/icons/calendar      | High       |
| lib/features/events/widgets/event_form_fields.dart     | Event Form           | `Icons.remove_rounded`              | Material | Decrement/remove   | `minus`            | https://lucide.dev/icons/minus         | High       |
| lib/features/events/widgets/event_form_fields.dart     | Event Form           | `Icons.library_music_rounded`       | Material | Setlist reference  | `library`          | https://lucide.dev/icons/library       | Medium     |
| lib/features/events/widgets/gig_form_fields.dart       | Gig Form             | `Icons.close`                       | Material | Decline response   | `x`                | https://lucide.dev/icons/x             | High       |
| lib/features/events/widgets/gig_form_fields.dart       | Gig Form             | `Icons.check`                       | Material | Accept response    | `check`            | https://lucide.dev/icons/check         | High       |
| lib/features/events/widgets/gig_form_fields.dart       | Gig Form             | `Icons.add_circle_outline_rounded`  | Material | Add item           | `plus-circle`      | https://lucide.dev/icons/plus-circle   | High       |
| lib/features/events/widgets/event_editor_drawer.dart   | Event Editor         | `Icons.close_rounded`               | Material | Close drawer       | `x`                | https://lucide.dev/icons/x             | High       |
| lib/features/events/widgets/event_editor_drawer.dart   | Event Editor         | `Icons.error_outline_rounded`       | Material | Validation error   | `circle-alert`     | https://lucide.dev/icons/circle-alert  | High       |
| lib/features/events/widgets/event_editor_drawer.dart   | Event Editor         | `Icons.calendar_today_rounded`      | Material | Date picker        | `calendar`         | https://lucide.dev/icons/calendar      | High       |
| lib/features/events/widgets/event_editor_helpers.dart  | Event Editor Helpers | `Icons.keyboard_arrow_down_rounded` | Material | Dropdown indicator | `chevron-down`     | https://lucide.dev/icons/chevron-down  | High       |

### Setlists & Songs

| File                                             | Screen/Component | Current Icon                   | Library  | Purpose              | Lucide Replacement | Lucide URL                              | Confidence |
| ------------------------------------------------ | ---------------- | ------------------------------ | -------- | -------------------- | ------------------ | --------------------------------------- | ---------- |
| lib/features/setlists/create_setlist_screen.dart | Create Setlist   | `Icons.close_rounded`          | Material | Close/cancel         | `x`                | https://lucide.dev/icons/x              | High       |
| lib/features/setlists/create_setlist_screen.dart | Create Setlist   | `Icons.queue_music_rounded`    | Material | Setlist icon         | `list-music`       | https://lucide.dev/icons/list-music     | High       |
| lib/features/setlists/new_setlist_screen.dart    | New Setlist      | `Icons.close_rounded`          | Material | Close modal          | `x`                | https://lucide.dev/icons/x              | High       |
| lib/features/setlists/new_setlist_screen.dart    | New Setlist      | `Icons.error_outline_rounded`  | Material | Error state          | `circle-alert`     | https://lucide.dev/icons/circle-alert   | High       |
| lib/features/setlists/new_setlist_screen.dart    | New Setlist      | `Icons.delete_outline_rounded` | Material | Delete song          | `trash-2`          | https://lucide.dev/icons/trash-2        | High       |
| lib/features/setlists/new_setlist_screen.dart    | New Setlist      | `Icons.edit_rounded`           | Material | Edit setlist         | `pencil`           | https://lucide.dev/icons/pencil         | High       |
| lib/features/setlists/new_setlist_screen.dart    | New Setlist      | `Icons.check_rounded`          | Material | Confirm action       | `check`            | https://lucide.dev/icons/check          | High       |
| lib/features/setlists/new_setlist_screen.dart    | New Setlist      | `Icons.music_note_rounded`     | Material | Song indicator       | `music`            | https://lucide.dev/icons/music          | High       |
| lib/features/setlists/new_setlist_screen.dart    | New Setlist      | `Icons.add_rounded`            | Material | Add song             | `plus`             | https://lucide.dev/icons/plus           | High       |
| lib/features/setlists/new_setlist_screen.dart    | New Setlist      | `Icons.warning_rounded`        | Material | Warning state        | `triangle-alert`   | https://lucide.dev/icons/triangle-alert | High       |
| lib/features/setlists/setlists_screen.dart       | Setlists Screen  | `Icons.error_outline_rounded`  | Material | Error state          | `circle-alert`     | https://lucide.dev/icons/circle-alert   | High       |
| lib/features/setlists/setlists_screen.dart       | Setlists Screen  | `Icons.add_rounded`            | Material | Add setlist          | `plus`             | https://lucide.dev/icons/plus           | High       |
| lib/features/setlists/setlists_tab_content.dart  | Setlists Tab     | `Icons.music_off_rounded`      | Material | No songs empty state | `music-off`        | https://lucide.dev/icons/music-off      | High       |
| lib/features/setlists/setlists_tab_content.dart  | Setlists Tab     | `Icons.refresh_rounded`        | Material | Refresh              | `refresh-cw`       | https://lucide.dev/icons/refresh-cw     | High       |
| lib/features/setlists/setlists_tab_content.dart  | Setlists Tab     | `Icons.add_rounded`            | Material | Add setlist          | `plus`             | https://lucide.dev/icons/plus           | High       |
| lib/features/setlists/setlist_detail_screen.dart | Setlist Detail   | `Icons.star`                   | Material | Favorite/featured    | `star`             | https://lucide.dev/icons/star           | High       |
| lib/features/setlists/setlist_detail_screen.dart | Setlist Detail   | `Icons.ios_share_rounded`      | Material | Share setlist        | `share`            | https://lucide.dev/icons/share          | High       |

### Setlist Widgets

| File                                                           | Screen/Component | Current Icon                   | Library  | Purpose            | Lucide Replacement | Lucide URL                             | Confidence |
| -------------------------------------------------------------- | ---------------- | ------------------------------ | -------- | ------------------ | ------------------ | -------------------------------------- | ---------- |
| lib/features/setlists/widgets/setlist_card.dart                | Setlist Card     | `Icons.star`                   | Material | Favorite marker    | `star`             | https://lucide.dev/icons/star          | High       |
| lib/features/setlists/widgets/setlist_card.dart                | Setlist Card     | `Icons.drag_indicator_rounded` | Material | Drag reorder grip  | `grip-vertical`    | https://lucide.dev/icons/grip-vertical | High       |
| lib/features/setlists/widgets/swipeable_setlist_card.dart      | Swipeable Card   | `Icons.delete_outline_rounded` | Material | Swipe to delete    | `trash-2`          | https://lucide.dev/icons/trash-2       | High       |
| lib/features/setlists/widgets/swipeable_setlist_card.dart      | Swipeable Card   | `Icons.copy_rounded`           | Material | Swipe to duplicate | `copy`             | https://lucide.dev/icons/copy          | High       |
| lib/features/setlists/widgets/song_card.dart                   | Song Card        | `Icons.drag_indicator_rounded` | Material | Drag reorder grip  | `grip-vertical`    | https://lucide.dev/icons/grip-vertical | High       |
| lib/features/setlists/widgets/song_card.dart                   | Song Card        | `Icons.lyrics_outlined`        | Material | View lyrics        | `text`             | https://lucide.dev/icons/text          | Medium     |
| lib/features/setlists/widgets/reorderable_song_card.dart       | Reorderable Card | `Icons.drag_indicator_rounded` | Material | Drag reorder grip  | `grip-vertical`    | https://lucide.dev/icons/grip-vertical | High       |
| lib/features/setlists/widgets/reorderable_song_card.dart       | Reorderable Card | `Icons.lyrics_outlined`        | Material | View lyrics        | `text`             | https://lucide.dev/icons/text          | Medium     |
| lib/features/setlists/widgets/reorderable_song_card.dart       | Reorderable Card | `Icons.edit_outlined`          | Material | Edit song          | `pencil`           | https://lucide.dev/icons/pencil        | High       |
| lib/features/setlists/widgets/song_details_bottom_sheet.dart   | Song Details     | `Icons.close_rounded`          | Material | Close sheet        | `x`                | https://lucide.dev/icons/x             | High       |
| lib/features/setlists/widgets/song_details_bottom_sheet.dart   | Song Details     | `Icons.edit_outlined`          | Material | Edit field         | `pencil`           | https://lucide.dev/icons/pencil        | High       |
| lib/features/setlists/widgets/song_details_bottom_sheet.dart   | Song Details     | `Icons.chevron_right_rounded`  | Material | Navigate forward   | `chevron-right`    | https://lucide.dev/icons/chevron-right | High       |
| lib/features/setlists/widgets/song_details_bottom_sheet.dart   | Song Details     | `Icons.edit_note`              | Material | Edit lyrics        | `file-pen-line`    | https://lucide.dev/icons/file-pen-line | High       |
| lib/features/setlists/widgets/song_details_bottom_sheet.dart   | Song Details     | `Icons.add`                    | Material | Add lyrics         | `plus`             | https://lucide.dev/icons/plus          | High       |
| lib/features/setlists/widgets/song_details_bottom_sheet.dart   | Song Details     | `Icons.play_circle_outline`    | Material | YouTube playback   | `play-circle`      | https://lucide.dev/icons/circle-play   | High       |
| lib/features/setlists/widgets/song_details_bottom_sheet.dart   | Song Details     | `Icons.close`                  | Material | Close YouTube      | `x`                | https://lucide.dev/icons/x             | High       |
| lib/features/setlists/widgets/action_buttons_row.dart          | Action Buttons   | `Icons.add_rounded`            | Material | Add song           | `plus`             | https://lucide.dev/icons/plus          | High       |
| lib/features/setlists/widgets/action_buttons_row.dart          | Action Buttons   | `Icons.ios_share_rounded`      | Material | Share setlist      | `share`            | https://lucide.dev/icons/share         | High       |
| lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart | Setlist Picker   | `Icons.close_rounded`          | Material | Close picker       | `x`                | https://lucide.dev/icons/x             | High       |
| lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart | Setlist Picker   | `Icons.add_rounded`            | Material | New setlist        | `plus`             | https://lucide.dev/icons/plus          | High       |
| lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart | Setlist Picker   | `Icons.queue_music_rounded`    | Material | Setlist icon       | `list-music`       | https://lucide.dev/icons/list-music    | High       |
| lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart | Setlist Picker   | `Icons.chevron_right_rounded`  | Material | Navigate forward   | `chevron-right`    | https://lucide.dev/icons/chevron-right | High       |
| lib/features/setlists/widgets/setlists_app_bar.dart            | Setlists App Bar | `Icons.arrow_back_ios_rounded` | Material | Back navigation    | `chevron-left`     | https://lucide.dev/icons/chevron-left  | High       |
| lib/features/setlists/widgets/setlists_app_bar.dart            | Setlists App Bar | `Icons.menu_rounded`           | Material | Open drawer        | `menu`             | https://lucide.dev/icons/menu          | High       |
| lib/features/setlists/widgets/back_only_app_bar.dart           | Back App Bar     | `Icons.arrow_back_ios_rounded` | Material | Back navigation    | `chevron-left`     | https://lucide.dev/icons/chevron-left  | High       |
| lib/features/setlists/widgets/empty_setlists_state.dart        | Empty Setlists   | `Icons.queue_music_rounded`    | Material | No setlists icon   | `list-music`       | https://lucide.dev/icons/list-music    | High       |
| lib/features/setlists/widgets/empty_setlists_state.dart        | Empty Setlists   | `Icons.add_rounded`            | Material | Create setlist CTA | `plus`             | https://lucide.dev/icons/plus          | High       |

### Song Lookup & Search

| File                                                      | Screen/Component | Current Icon                   | Library  | Purpose                  | Lucide Replacement | Lucide URL                            | Confidence |
| --------------------------------------------------------- | ---------------- | ------------------------------ | -------- | ------------------------ | ------------------ | ------------------------------------- | ---------- |
| lib/features/setlists/widgets/song_lookup_overlay.dart    | Song Lookup      | `Icons.chevron_left_rounded`   | Material | Back navigation          | `chevron-left`     | https://lucide.dev/icons/chevron-left | High       |
| lib/features/setlists/widgets/song_lookup_overlay.dart    | Song Lookup      | `Icons.close_rounded`          | Material | Close overlay            | `x`                | https://lucide.dev/icons/x            | High       |
| lib/features/setlists/widgets/song_lookup_overlay.dart    | Song Lookup      | `Icons.search_rounded`         | Material | Search action            | `search`           | https://lucide.dev/icons/search       | High       |
| lib/features/setlists/widgets/song_lookup_overlay.dart    | Song Lookup      | `Icons.error_outline_rounded`  | Material | Search error             | `circle-alert`     | https://lucide.dev/icons/circle-alert | High       |
| lib/features/setlists/widgets/song_lookup_overlay.dart    | Song Lookup      | `Icons.music_off_rounded`      | Material | No results               | `music-off`        | https://lucide.dev/icons/music-off    | High       |
| lib/features/setlists/widgets/song_lookup_overlay.dart    | Song Lookup      | `Icons.library_music_rounded`  | Material | Catalog section header   | `library`          | https://lucide.dev/icons/library      | Medium     |
| lib/features/setlists/widgets/song_lookup_overlay.dart    | Song Lookup      | `Icons.cloud_rounded`          | Material | External results section | `cloud`            | https://lucide.dev/icons/cloud        | High       |
| lib/features/setlists/widgets/song_lookup_overlay.dart    | Song Lookup      | `Icons.error_outline`          | Material | Error indicator          | `circle-alert`     | https://lucide.dev/icons/circle-alert | High       |
| lib/features/setlists/widgets/song_lookup_overlay.dart    | Song Lookup      | `Icons.music_note_rounded`     | Material | Song item icon           | `music`            | https://lucide.dev/icons/music        | High       |
| lib/features/setlists/widgets/bulk_add_songs_overlay.dart | Bulk Add Songs   | `Icons.arrow_back_ios_rounded` | Material | Back navigation          | `chevron-left`     | https://lucide.dev/icons/chevron-left | High       |
| lib/features/setlists/widgets/bulk_add_songs_overlay.dart | Bulk Add Songs   | `Icons.close_rounded`          | Material | Close overlay            | `x`                | https://lucide.dev/icons/x            | High       |
| lib/features/setlists/widgets/bulk_add_songs_overlay.dart | Bulk Add Songs   | `Icons.error_outline`          | Material | Error state              | `circle-alert`     | https://lucide.dev/icons/circle-alert | High       |

### Set Breaks & Pauses

| File                                                 | Screen/Component  | Current Icon                         | Library  | Purpose             | Lucide Replacement | Lucide URL                             | Confidence |
| ---------------------------------------------------- | ----------------- | ------------------------------------ | -------- | ------------------- | ------------------ | -------------------------------------- | ---------- |
| lib/features/setlists/widgets/set_break_creator.dart | Set Break Creator | `Icons.timer_outlined`               | Material | Timer/break icon    | `timer`            | https://lucide.dev/icons/timer         | High       |
| lib/features/setlists/widgets/set_break_creator.dart | Set Break Creator | `Icons.close_rounded`                | Material | Close creator       | `x`                | https://lucide.dev/icons/x             | High       |
| lib/features/setlists/widgets/set_break_creator.dart | Set Break Creator | `Icons.remove_rounded`               | Material | Decrease duration   | `minus`            | https://lucide.dev/icons/minus         | High       |
| lib/features/setlists/widgets/set_break_creator.dart | Set Break Creator | `Icons.add_rounded`                  | Material | Increase duration   | `plus`             | https://lucide.dev/icons/plus          | High       |
| lib/features/setlists/widgets/special_item_card.dart | Special Item Card | `Icons.timer_outlined`               | Material | Set break indicator | `timer`            | https://lucide.dev/icons/timer         | High       |
| lib/features/setlists/widgets/special_item_card.dart | Special Item Card | `Icons.pause_circle_outline_rounded` | Material | Pause indicator     | `circle-pause`     | https://lucide.dev/icons/circle-pause  | High       |
| lib/features/setlists/widgets/special_item_card.dart | Special Item Card | `Icons.drag_indicator_rounded`       | Material | Drag reorder grip   | `grip-vertical`    | https://lucide.dev/icons/grip-vertical | High       |
| lib/features/setlists/widgets/pause_creator.dart     | Pause Creator     | `Icons.pause_circle_outline_rounded` | Material | Pause icon          | `circle-pause`     | https://lucide.dev/icons/circle-pause  | High       |
| lib/features/setlists/widgets/pause_creator.dart     | Pause Creator     | `Icons.close_rounded`                | Material | Close creator       | `x`                | https://lucide.dev/icons/x             | High       |
| lib/features/setlists/widgets/pause_creator.dart     | Pause Creator     | `Icons.add_rounded`                  | Material | Add pause           | `plus`             | https://lucide.dev/icons/plus          | High       |

### Add to Setlist Workflow

| File                                                                     | Screen/Component | Current Icon                         | Library  | Purpose            | Lucide Replacement | Lucide URL                             | Confidence |
| ------------------------------------------------------------------------ | ---------------- | ------------------------------------ | -------- | ------------------ | ------------------ | -------------------------------------- | ---------- |
| lib/features/setlists/widgets/add_to_setlist/add_to_setlist_overlay.dart | Add to Setlist   | `Icons.chevron_left_rounded`         | Material | Back navigation    | `chevron-left`     | https://lucide.dev/icons/chevron-left  | High       |
| lib/features/setlists/widgets/add_to_setlist/add_to_setlist_overlay.dart | Add to Setlist   | `Icons.close_rounded`                | Material | Close overlay      | `x`                | https://lucide.dev/icons/x             | High       |
| lib/features/setlists/widgets/add_to_setlist/category_screen.dart        | Category Screen  | `Icons.search_rounded`               | Material | Search songs       | `search`           | https://lucide.dev/icons/search        | High       |
| lib/features/setlists/widgets/add_to_setlist/category_screen.dart        | Category Screen  | `Icons.edit_rounded`                 | Material | Manual entry       | `pencil`           | https://lucide.dev/icons/pencil        | High       |
| lib/features/setlists/widgets/add_to_setlist/category_screen.dart        | Category Screen  | `Icons.list_rounded`                 | Material | Bulk entry list    | `list`             | https://lucide.dev/icons/list          | High       |
| lib/features/setlists/widgets/add_to_setlist/category_screen.dart        | Category Screen  | `Icons.timer_outlined`               | Material | Set break category | `timer`            | https://lucide.dev/icons/timer         | High       |
| lib/features/setlists/widgets/add_to_setlist/category_screen.dart        | Category Screen  | `Icons.pause_circle_outline_rounded` | Material | Pause category     | `circle-pause`     | https://lucide.dev/icons/circle-pause  | High       |
| lib/features/setlists/widgets/add_to_setlist/category_screen.dart        | Category Screen  | `Icons.chevron_right_rounded`        | Material | Navigate forward   | `chevron-right`    | https://lucide.dev/icons/chevron-right | High       |
| lib/features/setlists/widgets/add_to_setlist/set_break_screen.dart       | Set Break Screen | `Icons.remove_rounded`               | Material | Decrease value     | `minus`            | https://lucide.dev/icons/minus         | High       |
| lib/features/setlists/widgets/add_to_setlist/set_break_screen.dart       | Set Break Screen | `Icons.add_rounded`                  | Material | Increase value     | `plus`             | https://lucide.dev/icons/plus          | High       |
| lib/features/setlists/widgets/add_to_setlist/set_break_screen.dart       | Set Break Screen | `Icons.delete_outline_rounded`       | Material | Delete break       | `trash-2`          | https://lucide.dev/icons/trash-2       | High       |
| lib/features/setlists/widgets/add_to_setlist/set_break_screen.dart       | Set Break Screen | `Icons.check_rounded`                | Material | Confirm break      | `check`            | https://lucide.dev/icons/check         | High       |
| lib/features/setlists/widgets/add_to_setlist/set_break_screen.dart       | Set Break Screen | `Icons.timer_outlined`               | Material | Timer icon         | `timer`            | https://lucide.dev/icons/timer         | High       |
| lib/features/setlists/widgets/add_to_setlist/pause_screen.dart           | Pause Screen     | `Icons.close_rounded`                | Material | Close              | `x`                | https://lucide.dev/icons/x             | High       |
| lib/features/setlists/widgets/add_to_setlist/pause_screen.dart           | Pause Screen     | `Icons.add_rounded`                  | Material | Add pause          | `plus`             | https://lucide.dev/icons/plus          | High       |
| lib/features/setlists/widgets/add_to_setlist/pause_screen.dart           | Pause Screen     | `Icons.delete_outline_rounded`       | Material | Delete pause       | `trash-2`          | https://lucide.dev/icons/trash-2       | High       |
| lib/features/setlists/widgets/add_to_setlist/pause_screen.dart           | Pause Screen     | `Icons.check_rounded`                | Material | Confirm            | `check`            | https://lucide.dev/icons/check         | High       |
| lib/features/setlists/widgets/add_to_setlist/pause_screen.dart           | Pause Screen     | `Icons.pause_circle_outline_rounded` | Material | Pause icon         | `circle-pause`     | https://lucide.dev/icons/circle-pause  | High       |
| lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart   | Original Song    | `Icons.add_rounded`                  | Material | Add song           | `plus`             | https://lucide.dev/icons/plus          | High       |
| lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart   | Original Song    | `Icons.delete_outline_rounded`       | Material | Delete             | `trash-2`          | https://lucide.dev/icons/trash-2       | High       |
| lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart      | Bulk Entry       | `Icons.close_rounded`                | Material | Close              | `x`                | https://lucide.dev/icons/x             | High       |
| lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart      | Bulk Entry       | `Icons.add_rounded`                  | Material | Add entry          | `plus`             | https://lucide.dev/icons/plus          | High       |

### Tuning & Instruments

| File                                                          | Screen/Component | Current Icon                   | Library  | Purpose            | Lucide Replacement | Lucide URL                       | Confidence |
| ------------------------------------------------------------- | ---------------- | ------------------------------ | -------- | ------------------ | ------------------ | -------------------------------- | ---------- |
| lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart | Tuning Picker    | `Icons.close_rounded`          | Material | Close picker       | `x`                | https://lucide.dev/icons/x       | High       |
| lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart | Tuning Picker    | `Icons.add_rounded`            | Material | Add custom tuning  | `plus`             | https://lucide.dev/icons/plus    | High       |
| lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart | Tuning Picker    | `Icons.check_rounded`          | Material | Selected indicator | `check`            | https://lucide.dev/icons/check   | High       |
| lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart | Tuning Picker    | `Icons.delete_outline_rounded` | Material | Delete tuning      | `trash-2`          | https://lucide.dev/icons/trash-2 | High       |
| lib/features/setlists/widgets/custom_tuning_modal.dart        | Custom Tuning    | `Icons.close_rounded`          | Material | Close modal        | `x`                | https://lucide.dev/icons/x       | High       |
| lib/features/setlists/widgets/custom_tuning_modal.dart        | Custom Tuning    | `Icons.info_outline_rounded`   | Material | Info tooltip       | `info`             | https://lucide.dev/icons/info    | High       |
| lib/features/setlists/widgets/selection_circle.dart           | Selection Circle | `Icons.check_rounded`          | Material | Selected state     | `check`            | https://lucide.dev/icons/check   | High       |

### Members & Team

| File                                                    | Screen/Component | Current Icon                   | Library  | Purpose           | Lucide Replacement  | Lucide URL                                 | Confidence |
| ------------------------------------------------------- | ---------------- | ------------------------------ | -------- | ----------------- | ------------------- | ------------------------------------------ | ---------- |
| lib/features/members/members_tab_content.dart           | Members Tab      | `Icons.error_outline_rounded`  | Material | Error state       | `circle-alert`      | https://lucide.dev/icons/circle-alert      | High       |
| lib/features/members/members_tab_content.dart           | Members Tab      | `Icons.refresh_rounded`        | Material | Refresh           | `refresh-cw`        | https://lucide.dev/icons/refresh-cw        | High       |
| lib/features/members/widgets/members_empty_state.dart   | Empty Members    | `Icons.people_outline_rounded` | Material | No members icon   | `users`             | https://lucide.dev/icons/users             | High       |
| lib/features/members/widgets/members_empty_state.dart   | Empty Members    | `Icons.person_add_outlined`    | Material | Invite members    | `user-plus`         | https://lucide.dev/icons/user-plus         | High       |
| lib/features/members/widgets/member_card.dart           | Member Card      | `Icons.phone_outlined`         | Material | Phone contact     | `phone`             | https://lucide.dev/icons/phone             | High       |
| lib/features/members/widgets/member_card.dart           | Member Card      | `Icons.mail_outline_rounded`   | Material | Email contact     | `mail`              | https://lucide.dev/icons/mail              | High       |
| lib/features/members/widgets/member_card.dart           | Member Card      | `Icons.location_on_outlined`   | Material | Member location   | `map-pin`           | https://lucide.dev/icons/map-pin           | High       |
| lib/features/members/widgets/member_card.dart           | Member Card      | `Icons.cake_outlined`          | Material | Birthday          | `cake`              | https://lucide.dev/icons/cake              | High       |
| lib/features/members/widgets/member_card.dart           | Member Card      | `Icons.more_vert`              | Material | More options menu | `ellipsis-vertical` | https://lucide.dev/icons/ellipsis-vertical | High       |
| lib/features/members/widgets/pending_invite_card.dart   | Pending Invite   | `Icons.mail_outline_rounded`   | Material | Email indicator   | `mail`              | https://lucide.dev/icons/mail              | High       |
| lib/features/members/widgets/pending_invite_card.dart   | Pending Invite   | `Icons.more_vert`              | Material | Invite actions    | `ellipsis-vertical` | https://lucide.dev/icons/ellipsis-vertical | High       |
| lib/features/members/widgets/pending_invite_card.dart   | Pending Invite   | `Icons.refresh`                | Material | Resend invite     | `refresh-cw`        | https://lucide.dev/icons/refresh-cw        | High       |
| lib/features/members/widgets/pending_invite_card.dart   | Pending Invite   | `Icons.close`                  | Material | Cancel invite     | `x`                 | https://lucide.dev/icons/x                 | High       |
| lib/features/members/widgets/role_management_sheet.dart | Role Management  | `Icons.close`                  | Material | Close sheet       | `x`                 | https://lucide.dev/icons/x                 | High       |
| lib/features/members/widgets/role_management_sheet.dart | Role Management  | `Icons.warning_amber_rounded`  | Material | Warning/caution   | `triangle-alert`    | https://lucide.dev/icons/triangle-alert    | High       |
| lib/features/members/widgets/role_management_sheet.dart | Role Management  | `Icons.person_remove_outlined` | Material | Remove member     | `user-minus`        | https://lucide.dev/icons/user-minus        | High       |
| lib/features/members/widgets/role_management_sheet.dart | Role Management  | `Icons.check`                  | Material | Confirm role      | `check`             | https://lucide.dev/icons/check             | High       |

### Band Form & Creation

| File                                     | Screen/Component | Current Icon                  | Library  | Purpose            | Lucide Replacement | Lucide URL                            | Confidence |
| ---------------------------------------- | ---------------- | ----------------------------- | -------- | ------------------ | ------------------ | ------------------------------------- | ---------- |
| lib/features/bands/band_form_screen.dart | Band Form        | `Icons.camera_alt_rounded`    | Material | Take photo         | `camera`           | https://lucide.dev/icons/camera       | High       |
| lib/features/bands/band_form_screen.dart | Band Form        | `Icons.photo_library_rounded` | Material | Photo library      | `image`            | https://lucide.dev/icons/image        | High       |
| lib/features/bands/band_form_screen.dart | Band Form        | `Icons.chevron_left_rounded`  | Material | Back navigation    | `chevron-left`     | https://lucide.dev/icons/chevron-left | High       |
| lib/features/bands/band_form_screen.dart | Band Form        | `Icons.check_rounded`         | Material | Confirm/save       | `check`            | https://lucide.dev/icons/check        | High       |
| lib/features/bands/band_form_screen.dart | Band Form        | `Icons.add_rounded`           | Material | Add member         | `plus`             | https://lucide.dev/icons/plus         | High       |
| lib/features/bands/band_form_screen.dart | Band Form        | `Icons.close_rounded`         | Material | Close/remove       | `x`                | https://lucide.dev/icons/x            | High       |
| lib/features/bands/band_form_screen.dart | Band Form        | `Icons.schedule_rounded`      | Material | Rehearsal schedule | `clock`            | https://lucide.dev/icons/clock        | High       |

### Notifications

| File                                                                   | Screen/Component      | Current Icon                          | Library  | Purpose               | Lucide Replacement | Lucide URL                             | Confidence |
| ---------------------------------------------------------------------- | --------------------- | ------------------------------------- | -------- | --------------------- | ------------------ | -------------------------------------- | ---------- |
| lib/features/notifications/notification_preferences_screen.dart        | Notification Prefs    | `Icons.arrow_back_ios`                | Material | Back navigation       | `chevron-left`     | https://lucide.dev/icons/chevron-left  | High       |
| lib/features/notifications/notification_preferences_screen.dart        | Notification Prefs    | `Icons.notifications_off_rounded`     | Material | Notifications off     | `bell-off`         | https://lucide.dev/icons/bell-off      | High       |
| lib/features/notifications/notification_settings_screen.dart           | Notification Settings | `Icons.arrow_back`                    | Material | Back navigation       | `arrow-left`       | https://lucide.dev/icons/arrow-left    | High       |
| lib/features/notifications/notification_settings_screen.dart           | Notification Settings | `Icons.info_outline`                  | Material | Info tooltip          | `info`             | https://lucide.dev/icons/info          | High       |
| lib/features/notifications/notification_settings_screen.dart           | Notification Settings | `Icons.notifications_outlined`        | Material | Notifications         | `bell`             | https://lucide.dev/icons/bell          | High       |
| lib/features/notifications/widgets/notification_permission_prompt.dart | Permission Prompt     | `Icons.notifications_active_outlined` | Material | Notifications active  | `bell-ring`        | https://lucide.dev/icons/bell-ring     | High       |
| lib/features/notifications/widgets/notification_permission_prompt.dart | Permission Prompt     | `Icons.close`                         | Material | Dismiss prompt        | `x`                | https://lucide.dev/icons/x             | High       |
| lib/features/notifications/widgets/notification_permission_prompt.dart | Permission Prompt     | `Icons.check_circle`                  | Material | Enabled indicator     | `circle-check`     | https://lucide.dev/icons/circle-check  | High       |
| lib/features/notifications/widgets/notification_permission_prompt.dart | Permission Prompt     | `Icons.arrow_forward_ios`             | Material | Navigate forward      | `chevron-right`    | https://lucide.dev/icons/chevron-right | High       |
| lib/features/notifications/widgets/notification_permission_prompt.dart | Permission Prompt     | `Icons.notifications_off_outlined`    | Material | Disabled indicator    | `bell-off`         | https://lucide.dev/icons/bell-off      | High       |
| lib/features/notifications/widgets/notification_card.dart              | Notification Card     | `Icons.music_note_rounded`            | Material | Setlist update notif  | `music`            | https://lucide.dev/icons/music         | High       |
| lib/features/notifications/widgets/notification_card.dart              | Notification Card     | `Icons.schedule_rounded`              | Material | Rehearsal notif       | `clock`            | https://lucide.dev/icons/clock         | High       |
| lib/features/notifications/widgets/notification_card.dart              | Notification Card     | `Icons.event_busy_rounded`            | Material | Event cancelled notif | `calendar-x`       | https://lucide.dev/icons/calendar-x    | High       |
| lib/features/notifications/widgets/notification_card.dart              | Notification Card     | `Icons.queue_music_rounded`           | Material | Setlist notif         | `list-music`       | https://lucide.dev/icons/list-music    | High       |
| lib/features/notifications/widgets/notification_card.dart              | Notification Card     | `Icons.how_to_reg_rounded`            | Material | Registration/invite   | `user-check`       | https://lucide.dev/icons/user-check    | High       |
| lib/features/notifications/widgets/notification_card.dart              | Notification Card     | `Icons.group_rounded`                 | Material | Member activity notif | `users`            | https://lucide.dev/icons/users         | High       |
| lib/features/notifications/widgets/notification_card.dart              | Notification Card     | `Icons.mail_rounded`                  | Material | Email/message notif   | `mail`             | https://lucide.dev/icons/mail          | High       |
| lib/features/notifications/widgets/notification_settings_modal.dart    | Notification Modal    | `Icons.notifications_off_rounded`     | Material | Notifications off     | `bell-off`         | https://lucide.dev/icons/bell-off      | High       |

### Profile & Account

| File                                        | Screen/Component | Current Icon               | Library  | Purpose         | Lucide Replacement | Lucide URL                            | Confidence |
| ------------------------------------------- | ---------------- | -------------------------- | -------- | --------------- | ------------------ | ------------------------------------- | ---------- |
| lib/features/profile/profile_screen.dart    | Profile Screen   | `Icons.arrow_back_rounded` | Material | Back navigation | `arrow-left`       | https://lucide.dev/icons/arrow-left   | High       |
| lib/features/profile/profile_screen.dart    | Profile Screen   | `Icons.edit_rounded`       | Material | Edit profile    | `pencil`           | https://lucide.dev/icons/pencil       | High       |
| lib/features/profile/profile_screen.dart    | Profile Screen   | `Icons.error_outline`      | Material | Error state     | `circle-alert`     | https://lucide.dev/icons/circle-alert | High       |
| lib/features/profile/my_profile_screen.dart | My Profile       | `Icons.arrow_back_rounded` | Material | Back navigation | `arrow-left`       | https://lucide.dev/icons/arrow-left   | High       |
| lib/features/profile/my_profile_screen.dart | My Profile       | `Icons.error_outline`      | Material | Error state     | `circle-alert`     | https://lucide.dev/icons/circle-alert | High       |
| lib/features/profile/my_profile_screen.dart | My Profile       | `Icons.close`              | Material | Close/cancel    | `x`                | https://lucide.dev/icons/x            | High       |

### Settings & Preferences

| File                                       | Screen/Component | Current Icon                    | Library  | Purpose               | Lucide Replacement | Lucide URL                              | Confidence |
| ------------------------------------------ | ---------------- | ------------------------------- | -------- | --------------------- | ------------------ | --------------------------------------- | ---------- |
| lib/features/settings/settings_screen.dart | Settings         | `Icons.notifications_outlined`  | Material | Notification settings | `bell`             | https://lucide.dev/icons/bell           | High       |
| lib/features/settings/settings_screen.dart | Settings         | `Icons.delete_forever_outlined` | Material | Delete account        | `trash-2`          | https://lucide.dev/icons/trash-2        | High       |
| lib/features/settings/settings_screen.dart | Settings         | `Icons.warning_amber_rounded`   | Material | Delete warning        | `triangle-alert`   | https://lucide.dev/icons/triangle-alert | High       |
| lib/features/settings/settings_screen.dart | Settings         | `Icons.arrow_back_rounded`      | Material | Back navigation       | `arrow-left`       | https://lucide.dev/icons/arrow-left     | High       |
| lib/features/settings/settings_screen.dart | Settings         | `Icons.chevron_right_rounded`   | Material | Menu chevron          | `chevron-right`    | https://lucide.dev/icons/chevron-right  | High       |

### Feedback & Reporting

| File                                         | Screen/Component | Current Icon                      | Library  | Purpose             | Lucide Replacement | Lucide URL                              | Confidence |
| -------------------------------------------- | ---------------- | --------------------------------- | -------- | ------------------- | ------------------ | --------------------------------------- | ---------- |
| lib/features/feedback/bug_report_screen.dart | Bug Report       | `Icons.arrow_back_rounded`        | Material | Back navigation     | `arrow-left`       | https://lucide.dev/icons/arrow-left     | High       |
| lib/features/feedback/bug_report_screen.dart | Bug Report       | `Icons.bug_report_outlined`       | Material | Bug report category | `bug`              | https://lucide.dev/icons/bug            | High       |
| lib/features/feedback/bug_report_screen.dart | Bug Report       | `Icons.lightbulb_outline_rounded` | Material | Feature request     | `lightbulb`        | https://lucide.dev/icons/lightbulb      | High       |
| lib/features/feedback/bug_report_screen.dart | Bug Report       | `Icons.warning_amber_rounded`     | Material | Warning indicator   | `triangle-alert`   | https://lucide.dev/icons/triangle-alert | High       |
| lib/features/feedback/bug_report_screen.dart | Bug Report       | `Icons.close_rounded`             | Material | Close report        | `x`                | https://lucide.dev/icons/x              | High       |
| lib/features/feedback/bug_report_screen.dart | Bug Report       | `Icons.copy_rounded`              | Material | Copy to clipboard   | `copy`             | https://lucide.dev/icons/copy           | High       |

### Lyrics

| File                                                 | Screen/Component | Current Icon                       | Library  | Purpose            | Lucide Replacement | Lucide URL                                                     | Confidence |
| ---------------------------------------------------- | ---------------- | ---------------------------------- | -------- | ------------------ | ------------------ | -------------------------------------------------------------- | ---------- |
| lib/features/lyrics/widgets/lyrics_view_screen.dart  | Lyrics View      | `Icons.arrow_back_ios_new`         | Material | Back navigation    | `chevron-left`     | https://lucide.dev/icons/chevron-left                          | High       |
| lib/features/lyrics/widgets/lyrics_view_screen.dart  | Lyrics View      | `Icons.text_decrease`              | Material | Decrease font size | `a-arrow-down`     | https://lucide.dev/icons/a-arrow-down                          | High       |
| lib/features/lyrics/widgets/lyrics_view_screen.dart  | Lyrics View      | `Icons.text_increase`              | Material | Increase font size | `a-arrow-up`       | https://lucide.dev/icons/a-arrow-up                            | High       |
| lib/features/lyrics/widgets/lyrics_view_screen.dart  | Lyrics View      | `Icons.add`                        | Material | Zoom in            | `plus`             | https://lucide.dev/icons/plus                                  | High       |
| lib/features/lyrics/widgets/lyrics_view_screen.dart  | Lyrics View      | `Icons.remove`                     | Material | Zoom out           | `minus`            | https://lucide.dev/icons/minus                                 | High       |
| lib/features/lyrics/widgets/lyrics_view_screen.dart  | Lyrics View      | `Icons.pause` / `Icons.play_arrow` | Material | Auto-scroll toggle | `pause` / `play`   | https://lucide.dev/icons/pause / https://lucide.dev/icons/play | High       |
| lib/features/lyrics/widgets/lyrics_editor_sheet.dart | Lyrics Editor    | `Icons.remove`                     | Material | Decrease           | `minus`            | https://lucide.dev/icons/minus                                 | High       |
| lib/features/lyrics/widgets/lyrics_editor_sheet.dart | Lyrics Editor    | `Icons.add`                        | Material | Increase           | `plus`             | https://lucide.dev/icons/plus                                  | High       |

### Landing Page & Marketing

| File                                                  | Screen/Component  | Current Icon                     | Library  | Purpose           | Lucide Replacement             | Lucide URL                              | Confidence |
| ----------------------------------------------------- | ----------------- | -------------------------------- | -------- | ----------------- | ------------------------------ | --------------------------------------- | ---------- |
| lib/features/landing/landing_page.dart                | Landing Page      | `Icons.arrow_upward`             | Material | Scroll to top     | `arrow-up`                     | https://lucide.dev/icons/arrow-up       | High       |
| lib/features/landing/widgets/features_section.dart    | Features Section  | `Icons.headset_rounded`          | Material | Gear/equipment    | `headphones`                   | https://lucide.dev/icons/headphones     | High       |
| lib/features/landing/widgets/features_section.dart    | Features Section  | `Icons.mic_rounded`              | Material | Rehearsals        | `mic`                          | https://lucide.dev/icons/mic            | High       |
| lib/features/landing/widgets/features_section.dart    | Features Section  | `Icons.calendar_month_rounded`   | Material | Gigs/calendar     | `calendar`                     | https://lucide.dev/icons/calendar       | High       |
| lib/features/landing/widgets/features_section.dart    | Features Section  | `Icons.queue_music_rounded`      | Material | Setlists          | `list-music`                   | https://lucide.dev/icons/list-music     | High       |
| lib/features/landing/widgets/value_section.dart       | Value Section     | `Icons.speed_rounded`            | Material | Fast/easy         | `gauge`                        | https://lucide.dev/icons/gauge          | High       |
| lib/features/landing/widgets/value_section.dart       | Value Section     | `Icons.music_note_rounded`       | Material | Music             | `music`                        | https://lucide.dev/icons/music          | High       |
| lib/features/landing/widgets/value_section.dart       | Value Section     | `Icons.phone_iphone_rounded`     | Material | Mobile experience | `smartphone`                   | https://lucide.dev/icons/smartphone     | High       |
| lib/features/landing/widgets/value_section.dart       | Value Section     | `Icons.cloud_sync_rounded`       | Material | Cloud sync        | `cloud`                        | https://lucide.dev/icons/cloud          | Medium     |
| lib/features/landing/widgets/hero_section.dart        | Hero Section      | `Icons.apple`                    | Material | iOS app link      | `apple`                        | https://lucide.dev/icons/apple          | High       |
| lib/features/landing/widgets/hero_section.dart        | Hero Section      | `Icons.web`                      | Material | Web app link      | `globe`                        | https://lucide.dev/icons/globe          | High       |
| lib/features/landing/widgets/download_section.dart    | Download Section  | `Icons.apple`                    | Material | iOS download      | `apple`                        | https://lucide.dev/icons/apple          | High       |
| lib/features/landing/widgets/download_section.dart    | Download Section  | `Icons.web`                      | Material | Web app link      | `globe`                        | https://lucide.dev/icons/globe          | High       |
| lib/features/landing/widgets/screenshots_section.dart | Screenshots       | `Icons.apple`                    | Material | iOS platform tab  | `apple`                        | https://lucide.dev/icons/apple          | High       |
| lib/features/landing/widgets/screenshots_section.dart | Screenshots       | `Icons.web`                      | Material | Web platform tab  | `globe`                        | https://lucide.dev/icons/globe          | High       |
| lib/features/landing/widgets/footer_section.dart      | Footer            | `Icons.camera_alt`               | Material | Instagram social  | `instagram`                    | https://lucide.dev/icons/instagram      | High       |
| lib/features/landing/widgets/footer_section.dart      | Footer            | `Icons.facebook`                 | Material | Facebook social   | `facebook`                     | https://lucide.dev/icons/facebook       | High       |
| lib/features/landing/widgets/footer_section.dart      | Footer            | `Icons.email_rounded`            | Material | Contact email     | `mail`                         | https://lucide.dev/icons/mail           | High       |
| lib/features/landing/widgets/social_section.dart      | Social Section    | `Icons.camera_alt`               | Material | Instagram link    | `instagram`                    | https://lucide.dev/icons/instagram      | High       |
| lib/features/landing/widgets/social_section.dart      | Social Section    | `Icons.facebook`                 | Material | Facebook link     | `facebook`                     | https://lucide.dev/icons/facebook       | High       |
| lib/features/landing/widgets/social_section.dart      | Social Section    | `Icons.arrow_forward`            | Material | Learn more CTA    | `arrow-right`                  | https://lucide.dev/icons/arrow-right    | High       |
| lib/features/landing/widgets/support_section.dart     | Support Section   | `Icons.forum_rounded`            | Material | Community forum   | `message-square`               | https://lucide.dev/icons/message-square | High       |
| lib/features/landing/widgets/community_section.dart   | Community Section | `Icons.forum_rounded`            | Material | Community         | `message-square`               | https://lucide.dev/icons/message-square | High       |
| lib/features/landing/widgets/community_section.dart   | Community Section | `Icons.tips_and_updates_rounded` | Material | Tips/updates      | `sparkles`                     | https://lucide.dev/icons/sparkles       | Medium     |
| lib/features/landing/widgets/community_section.dart   | Community Section | `Icons.lightbulb_rounded`        | Material | Ideas             | `lightbulb`                    | https://lucide.dev/icons/lightbulb      | High       |
| lib/features/landing/widgets/community_section.dart   | Community Section | `Icons.support_agent_rounded`    | Material | Support agent     | `headset`                      | https://lucide.dev/icons/headset        | High       |
| lib/features/landing/widgets/community_section.dart   | Community Section | `Icons.reddit`                   | Material | Reddit social     | No suitable Lucide replacement | —                                       | —          |

### Shared Widgets & Utilities

| File                                                 | Screen/Component | Current Icon                                   | Library  | Purpose           | Lucide Replacement          | Lucide URL                                                                | Confidence |
| ---------------------------------------------------- | ---------------- | ---------------------------------------------- | -------- | ----------------- | --------------------------- | ------------------------------------------------------------------------- | ---------- |
| lib/components/overlays/tips_and_tricks_overlay.dart | Tips Overlay     | `Icons.close_rounded`                          | Material | Close overlay     | `x`                         | https://lucide.dev/icons/x                                                | High       |
| lib/features/legal/privacy_policy_screen.dart        | Privacy Policy   | `Icons.arrow_back`                             | Material | Back navigation   | `arrow-left`                | https://lucide.dev/icons/arrow-left                                       | High       |
| lib/features/shell/no_band_shell.dart                | No Band Shell    | `Icons.menu_rounded`                           | Material | Open drawer       | `menu`                      | https://lucide.dev/icons/menu                                             | High       |
| lib/features/shell/no_band_shell.dart                | No Band Shell    | `Icons.groups_rounded`                         | Material | Groups/bands      | `users`                     | https://lucide.dev/icons/users                                            | High       |
| lib/shared/widgets/native_app_banner.dart            | App Banner       | `Icons.close`                                  | Material | Dismiss banner    | `x`                         | https://lucide.dev/icons/x                                                | High       |
| lib/shared/widgets/currency_input_field.dart         | Currency Input   | `Icons.clear`                                  | Material | Clear input       | `x`                         | https://lucide.dev/icons/x                                                | High       |
| lib/shared/widgets/banner_test_screen.dart           | Banner Test      | `Icons.refresh`                                | Material | Refresh test      | `refresh-cw`                | https://lucide.dev/icons/refresh-cw                                       | High       |
| lib/shared/widgets/banner_test_screen.dart           | Banner Test      | `Icons.block`                                  | Material | Block test        | `ban`                       | https://lucide.dev/icons/ban                                              | High       |
| lib/shared/widgets/banner_test_screen.dart           | Banner Test      | `Icons.terminal`                               | Material | Console test      | `terminal`                  | https://lucide.dev/icons/terminal                                         | High       |
| lib/shared/widgets/banner_test_screen.dart           | Banner Test      | `Icons.check_circle` / `Icons.cancel_outlined` | Material | Pass/fail status  | `circle-check` / `circle-x` | https://lucide.dev/icons/circle-check / https://lucide.dev/icons/circle-x | High       |
| lib/app/theme/app_animations.dart                    | App Animations   | `Icons.check_circle`                           | Material | Success animation | `circle-check`              | https://lucide.dev/icons/circle-check                                     | High       |

### SVG Assets (Non-Icon Imagery)

| File                                        | Screen/Component | Current Asset       | Library   | Purpose               | Lucide Replacement                            | Lucide URL | Confidence |
| ------------------------------------------- | ---------------- | ------------------- | --------- | --------------------- | --------------------------------------------- | ---------- | ---------- |
| assets/images/bandroadie_logo_optimized.svg | Animated Logo    | Brand logo SVG      | SVG Asset | App branding logo     | No suitable Lucide replacement (brand asset)  | —          | —          |
| assets/images/vip_only.svg                  | Restricted Tab   | VIP badge SVG       | SVG Asset | Premium feature gate  | No suitable Lucide replacement (custom brand) | —          | —          |
| assets/images/band_roadie_logo_tagline.svg  | Hero Section     | Logo + tagline SVG  | SVG Asset | Marketing hero logo   | No suitable Lucide replacement (brand asset)  | —          | —          |
| assets/images/bandroadie_logo.svg           | Various          | Logo variant SVG    | SVG Asset | Brand logo            | No suitable Lucide replacement (brand asset)  | —          | —          |
| assets/images/google_play_logo.svg          | Download Section | Google Play badge   | SVG Asset | Play Store link badge | No suitable Lucide replacement (brand asset)  | —          | —          |
| assets/images/bandroadie_horiz.svg          | Various          | Horizontal logo SVG | SVG Asset | Horizontal brand logo | No suitable Lucide replacement (brand asset)  | —          | —          |

### Web PWA Icons

| File                            | Screen/Component | Current Asset    | Library    | Purpose           | Lucide Replacement                           | Lucide URL | Confidence |
| ------------------------------- | ---------------- | ---------------- | ---------- | ----------------- | -------------------------------------------- | ---------- | ---------- |
| web/icons/Icon-192.png          | PWA Manifest     | 192x192 app icon | PNG Asset  | PWA install icon  | No suitable Lucide replacement (app icon)    | —          | —          |
| web/icons/Icon-512.png          | PWA Manifest     | 512x512 app icon | PNG Asset  | PWA splash icon   | No suitable Lucide replacement (app icon)    | —          | —          |
| web/icons/Icon-maskable-192.png | PWA Manifest     | 192x192 maskable | PNG Asset  | PWA adaptive icon | No suitable Lucide replacement (app icon)    | —          | —          |
| web/icons/Icon-maskable-512.png | PWA Manifest     | 512x512 maskable | PNG Asset  | PWA adaptive icon | No suitable Lucide replacement (app icon)    | —          | —          |
| web/index.html                  | Web Entry        | favicon.png      | PNG Asset  | Browser tab icon  | No suitable Lucide replacement (app icon)    | —          | —          |
| web/privacy.html                | Privacy Page     | Inline SVG logo  | SVG Inline | Brand header      | No suitable Lucide replacement (brand asset) | —          | —          |
| web/support.html                | Support Page     | Inline SVG logo  | SVG Inline | Brand header      | No suitable Lucide replacement (brand asset) | —          | —          |

---

## Icon Usage Summary

### Total Icons Found

- **~250+ individual icon instances** across the codebase
- **~75 unique Material Icon names** (many reused across screens)
- **6 SVG brand/logo assets** (not candidates for Lucide replacement)
- **5 PWA/web icon assets** (not candidates for Lucide replacement)

### Icons by Library

| Library                    | Count                       | Notes                                  |
| -------------------------- | --------------------------- | -------------------------------------- |
| Material Icons (`Icons.*`) | ~250 instances (~75 unique) | Primary icon source for all Flutter UI |
| SVG Assets                 | 6 files                     | Brand logos, badges — not replaceable  |
| PNG App Icons              | 5 files                     | PWA/favicon — not replaceable          |
| Inline SVG (web)           | 2 pages                     | Brand logo in HTML — not replaceable   |
| CupertinoIcons             | 0                           | Package exists in pubspec but unused   |
| Font Awesome / Other       | 0                           | No third-party icon libraries          |

### Most Frequently Used Icons (Duplicates Performing Same Function)

| Icon                                                          | Approx. Uses | Purpose                           |
| ------------------------------------------------------------- | ------------ | --------------------------------- |
| `Icons.close_rounded` / `Icons.close`                         | ~30+         | Close, dismiss, cancel actions    |
| `Icons.add_rounded` / `Icons.add`                             | ~25+         | Add, create, increment actions    |
| `Icons.error_outline_rounded` / `Icons.error_outline`         | ~15+         | Error states and validation       |
| `Icons.check_rounded` / `Icons.check`                         | ~12+         | Confirm, accept, select           |
| `Icons.chevron_right_rounded`                                 | ~8+          | Navigate forward, list disclosure |
| `Icons.chevron_left_rounded` / `Icons.arrow_back_ios_rounded` | ~8+          | Back navigation                   |
| `Icons.menu_rounded`                                          | 4            | Open side drawer                  |
| `Icons.queue_music_rounded`                                   | ~6+          | Setlist representation            |
| `Icons.music_note_rounded`                                    | ~5+          | Song/music representation         |
| `Icons.delete_outline_rounded`                                | ~7+          | Delete actions                    |
| `Icons.drag_indicator_rounded`                                | ~6           | Drag reorder grip handle          |
| `Icons.refresh_rounded` / `Icons.refresh`                     | ~6+          | Refresh/reload data               |
| `Icons.calendar_today_rounded`                                | ~4+          | Date/calendar picker              |

### Inconsistent Variants of Same Icon

| Purpose         | Variants Used                                                                                                                                | Recommended Lucide Standard     |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------- |
| Close/dismiss   | `Icons.close`, `Icons.close_rounded`                                                                                                         | `x`                             |
| Add/create      | `Icons.add`, `Icons.add_rounded`, `Icons.add_circle_outline_rounded`                                                                         | `plus` (or `plus-circle`)       |
| Error           | `Icons.error_outline`, `Icons.error_outline_rounded`                                                                                         | `circle-alert`                  |
| Check/confirm   | `Icons.check`, `Icons.check_rounded`, `Icons.check_circle`                                                                                   | `check` (or `circle-check`)     |
| Back navigation | `Icons.arrow_back`, `Icons.arrow_back_rounded`, `Icons.arrow_back_ios`, `Icons.arrow_back_ios_rounded`, `Icons.arrow_back_ios_new`           | `chevron-left` or `arrow-left`  |
| Refresh         | `Icons.refresh`, `Icons.refresh_rounded`                                                                                                     | `refresh-cw`                    |
| Notifications   | `Icons.notifications_outlined`, `Icons.notifications_off_rounded`, `Icons.notifications_off_outlined`, `Icons.notifications_active_outlined` | `bell`, `bell-off`, `bell-ring` |

---

## Migration Feasibility

### Difficulty Assessment: **Moderate**

The migration is straightforward because:

1. **Single icon library** — Only Material Icons are used for UI icons (no CupertinoIcons, no Font Awesome, no custom icon fonts)
2. **No icon abstraction layer exists** — Icons are referenced directly via `Icons.*` throughout the codebase, meaning a simple find-and-replace can handle most cases
3. **~75 unique icons** to map — manageable scope
4. **High Lucide coverage** — 97%+ of icons have direct High-confidence Lucide equivalents

### Icons Requiring Special Attention

| Icon                             | Concern                           | Recommendation                                                                                 |
| -------------------------------- | --------------------------------- | ---------------------------------------------------------------------------------------------- |
| `Icons.reddit`                   | No Lucide equivalent (brand icon) | Use `lucide_icons` for UI + a separate brand icon package (e.g., `simple_icons`) or custom SVG |
| `Icons.apple`                    | Lucide has `apple` icon           | Verify visual match for App Store context                                                      |
| `Icons.facebook`                 | Lucide has `facebook` icon        | Verify visual match for social context                                                         |
| `Icons.ios_share_rounded`        | iOS-specific share icon style     | `share` from Lucide is generic; may feel different on iOS                                      |
| `Icons.lyrics_outlined`          | No exact "lyrics" icon in Lucide  | `text` is the closest; consider `scroll-text` or custom SVG                                    |
| `Icons.library_music_rounded`    | Music library concept             | `library` is close but loses music connotation; could use `music-4`                            |
| `Icons.tips_and_updates_rounded` | Tips/sparkle concept              | `sparkles` is close but different connotation                                                  |
| `Icons.how_to_reg_rounded`       | Registration/verification         | `user-check` captures intent well                                                              |
| `Icons.queue_music_rounded`      | Music queue/setlist               | `list-music` is excellent match                                                                |

### Icons That Should Remain Unchanged

- **SVG brand assets** (logos, Google Play badge, VIP badge) — these are brand-specific and should not be replaced with generic icons
- **PWA app icons** (Icon-192.png, Icon-512.png, maskable variants) — platform-mandated assets
- **Web page inline SVG logos** — brand identity elements

---

## Recommended Migration Strategy

### Phase 1: Preparation

1. **Add `lucide_icons` package** to `pubspec.yaml`:
   ```yaml
   dependencies:
     lucide_icons: ^0.257.0 # or latest
   ```
2. **Remove `cupertino_icons`** from `pubspec.yaml` (confirmed unused)
3. **Create an icon abstraction layer** at `lib/app/theme/app_icons.dart`:

   ```dart
   import 'package:lucide_icons/lucide_icons.dart';

   /// Centralized icon registry for BandRoadie.
   /// Single source of truth — change icons in one place.
   class AppIcons {
     // Navigation
     static const home = LucideIcons.house;
     static const setlists = LucideIcons.listMusic;
     static const calendar = LucideIcons.calendar;
     static const members = LucideIcons.users;

     // Actions
     static const close = LucideIcons.x;
     static const add = LucideIcons.plus;
     static const delete = LucideIcons.trash2;
     static const edit = LucideIcons.pencil;
     static const check = LucideIcons.check;
     static const search = LucideIcons.search;
     static const share = LucideIcons.share;
     static const copy = LucideIcons.copy;
     static const refresh = LucideIcons.refreshCw;
     static const menu = LucideIcons.menu;

     // Status
     static const error = LucideIcons.circleAlert;
     static const warning = LucideIcons.triangleAlert;
     static const success = LucideIcons.circleCheck;
     static const info = LucideIcons.info;

     // Music
     static const musicNote = LucideIcons.music;
     static const musicOff = LucideIcons.musicOff;
     static const lyrics = LucideIcons.text;
     static const play = LucideIcons.play;
     static const pause = LucideIcons.pause;

     // ... etc
   }
   ```

### Phase 2: Incremental Replacement

4. **Replace icons screen-by-screen**, starting with the most-used patterns:
   - `Icons.close_rounded` → `AppIcons.close` (~30 instances)
   - `Icons.add_rounded` → `AppIcons.add` (~25 instances)
   - `Icons.error_outline_rounded` → `AppIcons.error` (~15 instances)
   - `Icons.check_rounded` → `AppIcons.check` (~12 instances)
5. **Normalize inconsistent variants** — e.g., unify `Icons.close` and `Icons.close_rounded` to a single `AppIcons.close`

### Phase 3: Cleanup & Verification

6. **Run `flutter analyze`** after each batch to catch type errors
7. **Visual regression testing** — compare before/after screenshots of key screens
8. **Remove Material Icons import** where no longer needed (Flutter includes it by default, so this is optional)
9. **For brand icons** (`Icons.reddit`, `Icons.facebook`, `Icons.apple`, `Icons.camera_alt` for Instagram):
   - Option A: Keep using Material Icons for just these few brand icons
   - Option B: Add `simple_icons` or `font_awesome_flutter` for brand logos only
   - Option C: Create custom SVG assets for the ~4 brand icons needed

### Phase 4: Ongoing Enforcement

10. **Add a lint rule or code review check** ensuring new icons use `AppIcons.*` instead of `Icons.*`
11. **Document the icon system** in the project's coding conventions

### Estimated Scope

- ~250 icon instances to update across ~50 files
- ~75 unique icon constants to map
- 4 brand icons need special handling
- 0 icons require custom design/SVG creation (beyond existing brand assets)
