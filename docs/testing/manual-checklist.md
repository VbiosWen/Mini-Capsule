# T4 Manual Verification Checklist

Run before each release on a real machine with Accessibility + (optionally) Automation
permissions granted. Each item closes the inventory row(s) noted. Record pass/fail + date.

| ID | Steps | Expected | Covers |
|----|-------|----------|--------|
| M1 | Copy text in app A → open Mini Capsule → click the text item's paste action while a TextEdit doc is focused | Text is pasted into TextEdit at the caret | #5 |
| M2 | Copy an image (e.g. screenshot) → paste the image item into Preview/Notes | Image appears in the target app | #5 |
| M3 | With another app focused, press the show/hide global hotkey | Capsule shows/hides regardless of focused app | #7 |
| M4 | With another app focused, press the quick-paste global hotkey | Front history item is pasted into the focused app | #7 |
| M5 | Open several app windows; observe the capsule | Capsule floats above all windows and appears on all Spaces | #13, #17 |
| M6 | Drag the capsule to a new location; quit and relaunch | Capsule reappears at the dragged location | #13 |
| M7 | Revoke Accessibility permission for Mini Capsule; trigger a paste | Paste no-ops gracefully; a `.error` event is logged (check Console.app, subsystem com.minicapsule.app) | #5 |
| M8 | Toggle "Launch at login" in settings; reboot | App launches (or not) per the setting | #15 |
| M9 | Click the menu-bar icon → pick a recent item | Item is copied/pasted per its action | #11, #17 |

**How to read logs during manual testing:** `log stream --predicate 'subsystem == "com.minicapsule.app"' --info`
or open Console.app and filter by subsystem. Never expect clipboard *content* in logs — only metadata.
