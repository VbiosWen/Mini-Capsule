# Keyboard Navigation & Text Preview Design

**Date:** 2026-07-06
**Status:** Approved

## Feature 1: Keyboard Navigation + Expansion Race Condition Fix

### Keyboard Navigation

When the capsule is expanded, the user can navigate the clip list with the keyboard:

- **↑ / ↓ arrow keys**: move selection up/down through the filtered items list.
- **Enter**: paste the selected item (calls the existing `onItemTap` handler).
- **Visual feedback**: the selected row gets a highlighted background (e.g. `.tertiary` fill) or accent border.

The search `TextField` retains focus while arrow keys control list navigation — this way the user can type to filter and press ↓ to navigate without losing the search field.

Implementation:
- Add `@State private var selectedItemID: UUID?` to `CapsuleExpandedView`.
- Use `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` in `.onAppear` (and remove in `.onDisappear`) to intercept ↑ / ↓ / Enter when the capsule is expanded. The local monitor runs before the TextField processes events, so arrow keys are consumed for list navigation while character input still reaches the search field for filtering.
- Arrow keys move the selection index within `filteredItems`. Clamp at ends (no wrap).
- When search text changes, reset selection to the first item.
- Enter triggers `onItemTap` for the selected item if one is selected.
- Keyboard monitor is only active when expanded — removed on collapse.
- `ClipItemRow` receives `isSelected: Bool` and applies highlight styling.

### Race Condition Fix

**Problem**: During the expand animation (~0.3s spring), the expanded view's list items are already laid out in their final positions. If the user is hovering over an area that will become the list, hover and click handlers fire before the animation completes, causing unexpected behavior (premature paste/delete, visual glitches).

**Solution**: Gate interaction on expansion readiness.

- `CapsuleView`: add `@State private var isExpandedReady = false`.
- When expansion starts (hover → `isExpanded = true`), set `isExpandedReady = false`.
- After the spring animation duration (0.35s, with a small buffer), set `isExpandedReady = true`.
- Pass `isExpandedReady` to `CapsuleExpandedView`.
- `CapsuleExpandedView`: when `isExpandedReady == false`, disable `.onTapGesture` on rows and suppress hover-based delete button; optionally show a subtle visual cue (e.g., items slightly dimmed).

Similarly, on collapse: reset `isExpandedReady = false` immediately.

### Files Affected
- `CapsuleView.swift` — add `isExpandedReady` state, dispatch after expand
- `CapsuleExpandedView.swift` — add `isExpandedReady` param, keyboard monitor, `selectedItemID` state
- `ClipItemRow.swift` — add `isSelected` param, gating on `interactive` / `isExpandedReady`

## Feature 2: Text Preview Popover

Text items get the same hover-preview treatment that images already have.

- In `ClipItemRow`, the existing popover gate is:
  ```
  isPresented: Binding(get: { isHovering && item.contentTypeRaw == "image" }, ...)
  ```
- Expand the condition to `(item.contentTypeRaw == "image" || item.contentTypeRaw == "text")`.
- Add a `textPreview` view: a `ScrollView` containing a `Text` with the full `item.textContent`, using `.textSelection(.enabled)` so the user can copy portions.
- Max dimensions: ~300×200, similar to the image preview's constraint approach.
- Font: `.system(size: 12, design: .monospaced)` for readability of raw text.

### Files Affected
- `ClipItemRow.swift` — extend popover condition, add `textPreview` view

## Testing

- **Keyboard nav**: expand the capsule, press ↓ repeatedly — selection highlight should move through items. Press Enter — selected item should paste. Search should still work (typing filters the list, selection resets to top).
- **Race condition**: hover over a position where the list will appear, watch the expand — items should not respond to clicks/hovers until the animation settles.
- **Text preview**: hover over a text row — popover should appear with full text content, scrollable if long.
