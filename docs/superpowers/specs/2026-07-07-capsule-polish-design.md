# Capsule Polish: Window Shape, Drag Smoothness, Default Position

Date: 2026-07-07

## Overview

Three targeted improvements to the macOS capsule floating panel:
1. Window shape follows the capsule clip (eliminate visible rectangular window edges)
2. Smoother drag tracking by replacing SwiftUI DragGesture with NSEvent monitoring
3. Default launch at top-center + "Reset Position" button in settings

## 1. Window Shape — Dynamic layer.cornerRadius

**Current state:** The borderless `NSPanel` is rectangular. SwiftUI clips content to a `Capsule()` shape internally, but the window itself has square corners, so rectangular edges are visible outside the capsule.

**Fix:** Set `cornerRadius` on the content view's backing layer, matching the logical shape size. Update it whenever the window resizes (expand/collapse).

### Values

| State | Size | cornerRadius |
|---|---|---|
| Collapsed (capsule) | 200×36 | 18 |
| Collapsed (dot) | 12×12 | 6 |
| Expanded | 280×360 | 12 |

### Implementation — `CapsuleWindowController.swift`

- In `init` / `setupWindow()`: set `contentView?.layer?.masksToBounds = true`
- In `observeExpandedState()` notification handler (where `setFrame` is called): also update `layer.cornerRadius` based on target size
- In the collapsed-style-change observer: update `cornerRadius` when switching between capsule and dot

### Edge Cases

- **Background image:** `CapsuleExpandedView` supports a custom background image. With `masksToBounds = true` on the contentView layer, the image is automatically clipped to the rounded corners — no additional mask needed.
- **Shadow:** `panel.hasShadow = false` remains (shadow is rendered by SwiftUI views, not the window). The rounded window shape doesn't affect shadow rendering.

---

## 2. Drag Smoothness — NSEvent Monitor

**Current state:** `CapsuleView.swift` implements drag via SwiftUI `DragGesture` with `onChanged`/`onEnded`. Each frame calls `panel.setFrame(_:display:true)`, forcing synchronous display updates. SwiftUI gesture overhead adds latency.

**Fix:** Remove the SwiftUI DragGesture entirely. Add a local NSEvent monitor in `CapsuleWindowController` that directly handles `.leftMouseDown`, `.leftMouseDragged`, and `.leftMouseUp` at the AppKit level.

### Implementation — `CapsuleWindowController.swift`

New method `startDragMonitoring()`:

```
mouseDown (event.window == self.window):
  → record mouseStartPoint
  → start 0.5s DispatchWorkItem (dragPrimer)
  → return event (don't consume — allows button clicks, TextField focus)

mouseDragged (dragPrimer NOT yet fired):
  → return event (don't move — user hasn't committed)

mouseDragged (dragPrimer fired):
  → if expanded: post .capsuleDragStarted notification (view collapses)
  → setFrameOrigin using event delta
  → return nil (consume event)

mouseUp:
  → cancel dragPrimer
  → save frame to UserDefaults
  → post .capsuleDragEnded notification
  → reset all drag state
  → return event
```

### Delta Calculation

```
mouseDragged event provides locationInWindow
  → delta = currentLocation - previousLocation
  → newOrigin.x += delta.x
  → newOrigin.y -= delta.y
  → window.setFrameOrigin(newOrigin)
```

Use `setFrameOrigin` (not `setFrame`) — no size change, no synchronous display flag, window server composites naturally.

### Removal from `CapsuleView.swift`

- Delete `windowDragGesture` computed property
- Delete `.simultaneousGesture(windowDragGesture)` modifier
- Delete all drag state `@State` vars: `isDragPrimed`, `isDragging`, `dragStartFrame`, `dragWorkItem`, `previousDragTranslation`
- Remove `isDragPrimed` parameter from `CapsuleExpandedView` and `CapsuleCollapsedView`
- Remove drag-primed visual effects from both collapsed variants (the white overlay background and shadow changes)

### Edge Cases

- **Clicks pass through:** mouseDown/mouseUp return the event unmodified, so gear button clicks, item taps, and TextField focus all work normally.
- **Hover expand during drag:** The existing hover logic in CapsuleView already checks drag state. After removing SwiftUI drag state, hover expand/collapse needs no change — it runs independently.
- **Multiple monitors:** NSEvent coordinates are in window space; `setFrameOrigin` works in screen coordinates. The delta is screen-space compatible since we're moving by offset, not absolute position.

---

## 3. Default Position + Reset Button

**Current state:** `CapsuleWindowController.loadFrame()` defaults to top-center if no saved position exists. Once dragged, position is saved and restored on next launch. No way to reset position except manually dragging.

**Fix:** Keep existing default logic. Add a "Reset Position" button in General Settings.

### Implementation — `GeneralSettingsView.swift`

Add a button in the floating-panel section:

```swift
Button("重置胶囊位置") {
    UserDefaults.standard.removeObject(forKey: "CapsuleWindowFrame")
    NotificationCenter.default.post(
        name: .resetCapsulePosition,
        object: nil
    )
}
```

### Implementation — `CapsuleWindowController.swift`

- Define `static let resetCapsulePosition = Notification.Name("resetCapsulePosition")`
- In `observeExpandedState()` (or a new observer), listen for `.resetCapsulePosition`
- On receipt: recalculate top-center frame using current screen, call `window.setFrame(newFrame, display: true, animate: true)`

### Default Frame Calculation

Already correct in `loadFrame()`:
- x = (screenWidth - capsuleWidth) / 2
- y = screenHeight - capsuleHeight - 40

The reset handler reuses this same calculation.

---

## Files Changed

| File | Change |
|---|---|
| `CapsuleWindowController.swift` | Add layer.cornerRadius management, NSEvent drag monitor, reset-position observer |
| `CapsuleView.swift` | Remove DragGesture, remove drag @State vars, remove isDragPrimed plumbing |
| `CapsuleExpandedView.swift` | Remove `isDragPrimed` parameter (already done via existing refactor) |
| `CapsuleCollapsedView.swift` | Remove `isDragPrimed` parameter and drag-primed visual effects |
| `GeneralSettingsView.swift` | Add reset-position button |

## Testing

- **Window shape:** Launch capsule → visually verify no rectangular edges outside pill shape. Switch to dot style → verify circular window. Hover expand → verify 12pt rounded corners.
- **Drag smoothness:** Drag capsule around screen — verify no jitter, no jump, natural 1:1 tracking. Verify click on gear opens settings (no regression). Verify 0.5s hold before drag activates.
- **Default position:** Clear saved frame → restart → verify top-center. Drag to new position → restart → verify restored. Click reset → verify immediate jump to top-center.
