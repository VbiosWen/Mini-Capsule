# Capsule Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three polish improvements to the macOS capsule: window shape follows capsule clip, smooth NSEvent-based drag, and reset-position button in settings.

**Architecture:** Move drag logic from SwiftUI DragGesture into CapsuleWindowController via NSEvent local monitor. Add dynamic layer.cornerRadius on the window's contentView. Post notifications for controller↔view communication during drag.

**Tech Stack:** SwiftUI, AppKit (NSPanel, NSEvent, CALayer), UserDefaults

## Global Constraints

- Deployment target: macOS 26.5 (equivalent), iOS 26.5, visionOS 26.5
- Swift 5.0
- All changes are macOS-only (`#if os(macOS)` already guards relevant files)
- Notification names defined as extensions on `NSNotification.Name` in `CapsuleView.swift`
- Keep existing hover expand/collapse logic intact

---

### Task 1: Define new notification names

**Files:**
- Modify: `Mini Capsule/UI/CapsuleView.swift:6-8`

**Interfaces:**
- Produces: `NSNotification.Name.capsuleDragStarted`, `NSNotification.Name.capsuleDragEnded`, `NSNotification.Name.resetCapsulePosition`

- [ ] **Step 1: Add notification name extensions**

Add the new notification names to the existing extension block at the top of `CapsuleView.swift`:

```swift
import SwiftUI
import SwiftData
import AppKit

extension NSNotification.Name {
    static let capsuleDidChangeExpanded = NSNotification.Name("capsuleDidChangeExpanded")
    static let capsuleDragStarted = NSNotification.Name("capsuleDragStarted")
    static let capsuleDragEnded = NSNotification.Name("capsuleDragEnded")
    static let resetCapsulePosition = NSNotification.Name("resetCapsulePosition")
}
```

- [ ] **Step 2: Commit**

```bash
git add "Mini Capsule/UI/CapsuleView.swift"
git commit -m "feat: add drag and reset notification names

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: CapsuleWindowController — dynamic layer.cornerRadius

**Files:**
- Modify: `Mini Capsule/UI/CapsuleWindowController.swift`

**Interfaces:**
- Consumes: (none new)
- Produces: `isExpanded` state tracked in controller; cornerRadius set on contentView.layer on init, expand/collapse, and style change

- [ ] **Step 1: Add isExpanded tracking and apply cornerRadius on init**

In `CapsuleWindowController`, add a property and modify `init`:

```swift
final class CapsuleWindowController: NSWindowController, NSWindowDelegate {
    private let modelContainer: ModelContainer
    private var isExpanded = false  // ADD

    // ... existing properties ...
```

In `init(modelContainer:)`, after `panel.contentView?.wantsLayer = true` (line 59), add:

```swift
panel.contentView?.wantsLayer = true
// Clip window to capsule shape
panel.contentView?.layer?.masksToBounds = true
let initialStyle = UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
panel.contentView?.layer?.cornerRadius = initialStyle == "dot" ? 6 : 18
```

- [ ] **Step 2: Update cornerRadius on expand/collapse**

In `observeExpandedState()`, inside the `.capsuleDidChangeExpanded` notification handler, add cornerRadius update right before `window.setFrame`:

```swift
let collapsedSize = self.currentCollapsedSize
let targetSize = isExpanded ? Self.expandedSize : collapsedSize
let currentFrame = window.frame

// Update cornerRadius before animated resize so it animates with the frame
let cornerRadius: CGFloat
if isExpanded {
    cornerRadius = 12
} else {
    let style = UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
    cornerRadius = style == "dot" ? 6 : 18
}
window.contentView?.layer?.cornerRadius = cornerRadius

let newFrame = NSRect(
    x: currentFrame.midX - targetSize.width / 2,
    y: currentFrame.maxY - targetSize.height,
    width: targetSize.width,
    height: targetSize.height
)

window.setFrame(newFrame, display: true, animate: true)
self.isExpanded = isExpanded  // ADD: track state

if isExpanded {
    NSApp.activate(ignoringOtherApps: true)
    window.makeKey()
}
```

- [ ] **Step 3: Update cornerRadius on collapsed style change**

Replace the empty `UserDefaults.didChangeNotification` observer body (around lines 63-67 in `observeExpandedState`). Find this block:

```swift
NotificationCenter.default.addObserver(
    forName: UserDefaults.didChangeNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    guard let self = self, let window = self.window else { return }
    // If currently collapsed, resize to new collapsed size
    // (expanded state is managed by CapsuleView hover logic)
}
```

Replace with:

```swift
NotificationCenter.default.addObserver(
    forName: UserDefaults.didChangeNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    guard let self = self, let window = self.window else { return }
    // If collapsed, update cornerRadius to match current style
    if !self.isExpanded {
        let style = UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
        let radius: CGFloat = style == "dot" ? 6 : 18
        window.contentView?.layer?.cornerRadius = radius

        // Also resize window to match new collapsed size
        let size = style == "dot" ? Self.dotCollapsedSize : Self.capsuleCollapsedSize
        if window.frame.size != size {
            let newFrame = NSRect(
                x: window.frame.midX - size.width / 2,
                y: window.frame.maxY - size.height,
                width: size.width,
                height: size.height
            )
            window.setFrame(newFrame, display: true, animate: true)
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add "Mini Capsule/UI/CapsuleWindowController.swift"
git commit -m "feat: add dynamic cornerRadius to capsule window

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: CapsuleWindowController — NSEvent drag monitor

**Files:**
- Modify: `Mini Capsule/UI/CapsuleWindowController.swift`

**Interfaces:**
- Consumes: `NSNotification.Name.capsuleDragStarted`, `NSNotification.Name.capsuleDragEnded`
- Produces: `startDragMonitoring()`, new private properties `dragMonitor`, `dragPrimer`, `isDragActive`, `previousDragLocation`

- [ ] **Step 1: Add drag state properties to CapsuleWindowController**

Add after the existing private properties:

```swift
final class CapsuleWindowController: NSWindowController, NSWindowDelegate {
    // ... existing properties ...

    // Drag monitoring
    private var dragMonitor: Any?
    private var dragPrimer: DispatchWorkItem?
    private var isDragActive = false
    private var previousDragLocation: NSPoint?
```

- [ ] **Step 2: Add startDragMonitoring() method**

Add the method to `CapsuleWindowController`:

```swift
private func startDragMonitoring() {
    dragMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
    ) { [weak self] event in
        guard let self = self, event.window == self.window else { return event }

        switch event.type {
        case .leftMouseDown:
            self.previousDragLocation = event.locationInWindow
            self.isDragActive = false

            let primer = DispatchWorkItem {
                self.isDragActive = true
                NotificationCenter.default.post(
                    name: .capsuleDragStarted,
                    object: nil
                )
            }
            self.dragPrimer = primer
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: primer)
            return event

        case .leftMouseDragged:
            let current = event.locationInWindow
            if self.isDragActive, let prev = self.previousDragLocation {
                let dx = current.x - prev.x
                let dy = current.y - prev.y
                var origin = self.window?.frame.origin ?? .zero
                origin.x += dx
                origin.y -= dy
                self.window?.setFrameOrigin(origin)
            }
            self.previousDragLocation = current
            return self.isDragActive ? nil : event

        case .leftMouseUp:
            self.dragPrimer?.cancel()
            self.dragPrimer = nil
            self.isDragActive = false
            self.previousDragLocation = nil
            self.saveFrame()
            NotificationCenter.default.post(
                name: .capsuleDragEnded,
                object: nil
            )
            return event

        default:
            return event
        }
    }
}
```

- [ ] **Step 3: Call startDragMonitoring from init**

In the `init(modelContainer:)` method of `CapsuleWindowController`, add `startDragMonitoring()` after `observeExpandedState()`:

```swift
observeExpandedState()
startDragMonitoring()  // ADD
```

- [ ] **Step 4: Add deinit to clean up monitor**

Add cleanup in `CapsuleWindowController`:

```swift
deinit {
    if let monitor = dragMonitor {
        NSEvent.removeMonitor(monitor)
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add "Mini Capsule/UI/CapsuleWindowController.swift"
git commit -m "feat: replace SwiftUI drag with NSEvent monitor for smooth dragging

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: CapsuleWindowController — reset position observer

**Files:**
- Modify: `Mini Capsule/UI/CapsuleWindowController.swift`

**Interfaces:**
- Consumes: `NSNotification.Name.resetCapsulePosition`
- Produces: Observer that resets window to top-center on notification

- [ ] **Step 1: Add reset observer**

Add the observer at the end of `observeExpandedState()` in `CapsuleWindowController`:

```swift
// Listen for reset position request
NotificationCenter.default.addObserver(
    forName: .resetCapsulePosition,
    object: nil,
    queue: .main
) { [weak self] _ in
    guard let self = self,
          let window = self.window,
          let screen = NSScreen.main else { return }

    let style = UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
    let size = style == "dot" ? Self.dotCollapsedSize : Self.capsuleCollapsedSize
    let screenWidth = screen.visibleFrame.width
    let screenHeight = screen.visibleFrame.maxY

    let x = (screenWidth - size.width) / 2
    let y = screenHeight - size.height - 40
    let newFrame = NSRect(x: x, y: y, width: size.width, height: size.height)

    window.setFrame(newFrame, display: true, animate: true)
    UserDefaults.standard.removeObject(forKey: Self.frameKey)
}
```

- [ ] **Step 2: Commit**

```bash
git add "Mini Capsule/UI/CapsuleWindowController.swift"
git commit -m "feat: add reset capsule position observer

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: CapsuleView — remove DragGesture, add drag notification listeners

**Files:**
- Modify: `Mini Capsule/UI/CapsuleView.swift`

**Interfaces:**
- Consumes: `NSNotification.Name.capsuleDragStarted`, `NSNotification.Name.capsuleDragEnded`
- Produces: Simplified CapsuleView with no drag gesture, `isDragging` state driven by notifications

- [ ] **Step 1: Remove all drag-related @State vars**

Delete these six lines from the `CapsuleView` struct (lines 21-25):

```swift
    // Long-press drag state
    @State private var isDragPrimed = false
    @State private var isDragging = false
    @State private var dragStartFrame: NSRect?
    @State private var dragWorkItem: DispatchWorkItem?
    @State private var previousDragTranslation: CGSize?
```

Replace with a single lightweight state:

```swift
    // Drag state — driven by CapsuleWindowController NSEvent monitor
    @State private var isDragging = false
```

- [ ] **Step 2: Remove windowDragGesture computed property**

Delete the entire `windowDragGesture` computed property (lines 111-177):

```swift
    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // ... delete all of this ...
            }
            .onEnded { _ in
                // ... delete all of this ...
            }
    }
```

- [ ] **Step 3: Update body — remove isDragPrimed from subview calls**

In the `body` computed property, update the subview instantiation to not pass `isDragPrimed`. Change:

```swift
            if isExpanded {
                CapsuleExpandedView(
                    searchText: $searchText,
                    isDragPrimed: isDragPrimed,
                    isExpandedReady: isExpandedReady,
                    onItemTap: { item in
```

To:

```swift
            if isExpanded {
                CapsuleExpandedView(
                    searchText: $searchText,
                    isExpandedReady: isExpandedReady,
                    onItemTap: { item in
```

And change:

```swift
                CapsuleCollapsedView(
                    latestItem: items.first,
                    isCapturing: isCapturing,
                    isDragPrimed: isDragPrimed,
                    collapsedStyle: UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
                )
```

To:

```swift
                CapsuleCollapsedView(
                    latestItem: items.first,
                    isCapturing: isCapturing,
                    collapsedStyle: UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
                )
```

- [ ] **Step 4: Remove .simultaneousGesture modifier, add drag notification listeners**

Remove `.simultaneousGesture(windowDragGesture)` from the view chain (line 57). Then, update the body to add drag notification listeners.

Find the chain:
```swift
        }
        .simultaneousGesture(windowDragGesture)
        .opacity(windowOpacity)
```

Replace with:
```swift
        }
        .opacity(windowOpacity)
```

Then add drag notification listeners after `.onHover` and before `.onChange`:

```swift
        .onReceive(NotificationCenter.default.publisher(for: .capsuleDragStarted)) { _ in
            isDragging = true
            if isExpanded {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isExpanded = false
                }
                postExpandedNotification()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .capsuleDragEnded)) { _ in
            isDragging = false
        }
```

- [ ] **Step 5: Simplify hover guard**

In the `.onHover` closure, change the guard from:

```swift
            if dragWorkItem != nil || isDragPrimed || isDragging { return }
```

To:

```swift
            if isDragging { return }
```

- [ ] **Step 6: Update .onChange of items to keep TextField input active**

The `.onChange(of: items.first?.id)` block can be simplified — it no longer needs to import AppKit for gesture, but the rest stays the same:

```swift
        .onChange(of: items.first?.id) { _, _ in
            isCapturing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isCapturing = false
            }
        }
```

No change needed here — just verify the block remains.

- [ ] **Step 7: Remove unused `import AppKit` if no longer needed**

Check if `AppKit` is still needed in `CapsuleView.swift`. The `NSNotification.Name` extension needs it, and `windowOpacity` doesn't use AppKit directly. But `postExpandedNotification` might. Keep the import — it's still used by the notification extension and doesn't hurt.

- [ ] **Step 8: Commit**

```bash
git add "Mini Capsule/UI/CapsuleView.swift"
git commit -m "refactor: remove DragGesture, use notification-driven drag state

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: CapsuleCollapsedView — remove isDragPrimed and visual effects

**Files:**
- Modify: `Mini Capsule/UI/CapsuleCollapsedView.swift`

**Interfaces:**
- Consumes: (none new)
- Produces: Simplified CapsuleCollapsedView without drag-primed visual state

- [ ] **Step 1: Remove isDragPrimed parameter**

Change the struct declaration from:

```swift
struct CapsuleCollapsedView: View {
    let latestItem: ClipItem?
    let isCapturing: Bool
    let isDragPrimed: Bool
    let collapsedStyle: String
```

To:

```swift
struct CapsuleCollapsedView: View {
    let latestItem: ClipItem?
    let isCapturing: Bool
    let collapsedStyle: String
```

- [ ] **Step 2: Simplify dotView — remove drag-primed effects**

Replace the `dotView` computed property entirely:

```swift
    private var dotView: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 12, height: 12)
            .scaleEffect(isCapturing ? 1.3 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: isCapturing)
            .shadow(
                color: .black.opacity(0.15),
                radius: 4,
                y: 2
            )
    }
```

- [ ] **Step 3: Simplify capsuleView — remove drag-primed effects**

Replace the `capsuleView` computed property entirely:

```swift
    private var capsuleView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isCapturing ? Color.blue : Color.green)
                .frame(width: 8, height: 8)
                .scaleEffect(isCapturing ? 1.3 : 1.0)
                .animation(.easeInOut(duration: 0.3), value: isCapturing)

            Text(summaryText)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(width: 200, height: 36)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
        }
        .clipShape(Capsule())
        .shadow(
            color: .black.opacity(0.15),
            radius: 8,
            y: 4
        )
    }
```

- [ ] **Step 4: Commit**

```bash
git add "Mini Capsule/UI/CapsuleCollapsedView.swift"
git commit -m "refactor: remove drag-primed visual effects from collapsed view

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: CapsuleExpandedView — remove isDragPrimed parameter

**Files:**
- Modify: `Mini Capsule/UI/CapsuleExpandedView.swift`

**Interfaces:**
- Consumes: (none new)
- Produces: Simplified CapsuleExpandedView without drag-primed visual state, cornerRadius 12

- [ ] **Step 1: Remove isDragPrimed parameter**

Change the struct declaration from:

```swift
struct CapsuleExpandedView: View {
    @Binding var searchText: String
    let isDragPrimed: Bool
    let isExpandedReady: Bool
    var onItemTap: (ClipItem) -> Void
    var onItemDelete: (ClipItem) -> Void
```

To:

```swift
struct CapsuleExpandedView: View {
    @Binding var searchText: String
    let isExpandedReady: Bool
    var onItemTap: (ClipItem) -> Void
    var onItemDelete: (ClipItem) -> Void
```

- [ ] **Step 2: Simplify background, clipShape, overlay, and shadow**

Replace the modifiers from `.frame(width: 280, height: 360)` through `.animation(...)` at lines 89-127. Find:

```swift
        .frame(width: 280, height: 360)
        .background {
            ZStack {
                // Background image (if set)
                if let imageData = UserDefaults.standard.data(forKey: "backgroundImageData"),
                   let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }

                Rectangle()
                    .fill(.ultraThinMaterial)
                if isDragPrimed {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            if isDragPrimed {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        }
        .shadow(
            color: isDragPrimed ? .white.opacity(0.2) : .black.opacity(0.2),
            radius: isDragPrimed ? 8 : 12,
            y: isDragPrimed ? 3 : 6
        )
        .animation(.easeInOut(duration: 0.2), value: isDragPrimed)
```

Replace with:

```swift
        .frame(width: 280, height: 360)
        .background {
            ZStack {
                // Background image (if set)
                if let imageData = UserDefaults.standard.data(forKey: "backgroundImageData"),
                   let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }

                Rectangle()
                    .fill(.ultraThinMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(
            color: .black.opacity(0.2),
            radius: 12,
            y: 6
        )
```

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/UI/CapsuleExpandedView.swift"
git commit -m "refactor: remove isDragPrimed from expanded view, simplify visuals

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: GeneralSettingsView — add reset position button

**Files:**
- Modify: `Mini Capsule/Settings/GeneralSettingsView.swift`

**Interfaces:**
- Consumes: `NSNotification.Name.resetCapsulePosition`
- Produces: Button in UI that clears saved frame and posts reset notification

- [ ] **Step 1: Add reset button in the floating panel behavior section**

In the "悬浮窗行为" section (Floating Panel Behavior), after the hover collapse delay picker and before the section closing `}`, add the reset button. Insert at line 84 (after the collapse delay picker's `.disabled` line and before the section `}`):

```swift
                .disabled(!settings.showFloatingPanel)

                Button("重置胶囊位置") {
                    UserDefaults.standard.removeObject(forKey: "CapsuleWindowFrame")
                    NotificationCenter.default.post(
                        name: .resetCapsulePosition,
                        object: nil
                    )
                }
                .disabled(!settings.showFloatingPanel)
```

- [ ] **Step 2: Commit**

```bash
git add "Mini Capsule/Settings/GeneralSettingsView.swift"
git commit -m "feat: add reset capsule position button in general settings

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: Build and verify

**Files:** (none — verification only)

**Interfaces:** (none)

- [ ] **Step 1: Build for macOS**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 2: Visual verification checklist**

Build and run the app, then verify:

1. **Window shape:** Launch capsule → verify no rectangular edges visible outside pill shape. Switch to "圆点" collapsed style → verify circular window. Hover expand → verify 12pt rounded corners on expanded panel.
2. **Drag smoothness:** Press and hold on capsule for 0.5s, then drag around screen. Verify smooth 1:1 tracking with no jitter or jump. Click on gear icon (without holding) → verify Settings opens (no regression). Click on a clip item in expanded view → verify tap works (no regression).
3. **Default position:** Clear saved frame (delete `CapsuleWindowFrame` from UserDefaults or use the reset button). Restart app → verify capsule appears at top-center of screen. Drag to a new position → restart → verify position is restored. Click "重置胶囊位置" in Settings → verify immediate jump to top-center.

- [ ] **Step 3: Commit (if any final tweaks needed)**

```bash
git add -A
git commit -m "chore: final verification tweaks for capsule polish

Co-Authored-By: Claude <noreply@anthropic.com>"
```
