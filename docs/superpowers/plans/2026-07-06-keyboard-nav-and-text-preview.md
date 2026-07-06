# Keyboard Navigation & Text Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add keyboard navigation (↑/↓/Enter) to the expanded capsule view, fix a race condition where hover/click fires during the expand animation, and add text content popover preview on hover (matching the existing image preview pattern).

**Architecture:** Three files modified — `CapsuleView` gates expansion readiness with a boolean state passed downstream; `CapsuleExpandedView` owns keyboard monitoring and selection state; `ClipItemRow` receives new props for selection highlight, interaction gating, and text preview.

**Tech Stack:** SwiftUI, AppKit (NSEvent local monitor), SwiftData (existing ClipItem model)

## Global Constraints

- Deployment target: macOS 26.5 (Apple internal versioning)
- Must not break existing drag gesture or hover expand/collapse behavior
- Must not break existing image popover preview
- Search TextField must remain functional while arrow keys control list navigation

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Mini Capsule/UI/CapsuleView.swift` | Modify | Add `isExpandedReady` state, pass to expanded view |
| `Mini Capsule/UI/CapsuleExpandedView.swift` | Modify | Keyboard event monitor, selected item tracking, readiness gating |
| `Mini Capsule/UI/ClipItemRow.swift` | Modify | Selected highlight, interaction gating, text preview popover |

---

### Task 1: Add `isExpandedReady` to CapsuleView and pass to CapsuleExpandedView

**Files:**
- Modify: `Mini Capsule/UI/CapsuleView.swift`

**Interfaces:**
- Produces: `@State private var isExpandedReady = false` in CapsuleView, passed as `isExpandedReady: Bool` to CapsuleExpandedView

---

- [ ] **Step 1: Add `isExpandedReady` state**

Add after line 17 (the `@State private var searchText = ""` line):

```swift
    @State private var isExpanded = false
    @State private var isCapturing = false
    @State private var searchText = ""
    @State private var hoverWorkItem: DispatchWorkItem?
    @State private var isExpandedReady = false
```

- [ ] **Step 2: Set `isExpandedReady = false` on expand, `true` after animation delay**

Replace the expand section in `.onHover` (lines 66-75) — add readiness gating:

```swift
            if hovering {
                isExpandedReady = false
                let workItem = DispatchWorkItem {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded = true
                        searchText = ""
                    }
                    postExpandedNotification()
                    // Enable row interaction after expand animation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        isExpandedReady = true
                    }
                }
                hoverWorkItem = workItem
                let effectiveExpandDelay = hoverExpandDelay > 0 ? hoverExpandDelay : 0.3
                DispatchQueue.main.asyncAfter(deadline: .now() + effectiveExpandDelay, execute: workItem)
```

- [ ] **Step 3: Set `isExpandedReady = false` on collapse**

Replace the collapse section in `.onHover` (lines 76-86):

```swift
            } else {
                isExpandedReady = false
                let workItem = DispatchWorkItem {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isExpanded = false
                    }
                    postExpandedNotification()
                }
                hoverWorkItem = workItem
                let effectiveCollapseDelay = hoverCollapseDelay > 0 ? hoverCollapseDelay : 1.0
                DispatchQueue.main.asyncAfter(deadline: .now() + effectiveCollapseDelay, execute: workItem)
            }
```

- [ ] **Step 4: Pass `isExpandedReady` to `CapsuleExpandedView`**

Replace the `CapsuleExpandedView(...)` call (around line 29):

```swift
            if isExpanded {
                CapsuleExpandedView(
                    searchText: $searchText,
                    isDragPrimed: isDragPrimed,
                    isExpandedReady: isExpandedReady,
                    onItemTap: { item in
```

- [ ] **Step 5: Build to verify**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED** (note: CapsuleExpandedView will have a compile error until Task 2 adds the new parameter)

- [ ] **Step 6: Commit**

```bash
git add "Mini Capsule/UI/CapsuleView.swift"
git commit -m "feat: add isExpandedReady gating to CapsuleView expand/collapse

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Add keyboard navigation and readiness gating to CapsuleExpandedView

**Files:**
- Modify: `Mini Capsule/UI/CapsuleExpandedView.swift`

**Interfaces:**
- Consumes: `isExpandedReady: Bool` from CapsuleView (Task 1)
- Produces: `selectedItemID: UUID?` state, keyboard event monitor, passes `isSelected` and `isInteractive` to ClipItemRow

---

- [ ] **Step 1: Add `isExpandedReady` parameter and `selectedItemID` state**

Replace the struct declaration and properties (lines 6-15):

```swift
struct CapsuleExpandedView: View {
    @Binding var searchText: String
    let isDragPrimed: Bool
    let isExpandedReady: Bool
    var onItemTap: (ClipItem) -> Void
    var onItemDelete: (ClipItem) -> Void

    @Query(
        sort: [SortDescriptor(\ClipItem.timestamp, order: .reverse)]
    ) private var allItems: [ClipItem]

    @FocusState private var isSearchFocused: Bool
    @State private var selectedItemID: UUID?
```

- [ ] **Step 2: Add keyboard event monitor**

Add to the `body` view, before the `VStack` closing (after `.onAppear` at line 124). Replace the existing `.onAppear` block:

```swift
        .onAppear {
            isSearchFocused = true
        }
        .onDisappear {
            selectedItemID = nil
        }
        .background(KeyboardMonitorView(
            filteredItems: filteredItems,
            selectedItemID: $selectedItemID,
            onSelect: { item in
                onItemTap(item)
            }
        ))
```

- [ ] **Step 3: Define `KeyboardMonitorView` as a fileprivate NSViewRepresentable**

Add at the bottom of `CapsuleExpandedView.swift`, after the closing `}` of `CapsuleExpandedView`:

```swift
// MARK: - Keyboard Monitor (NSViewRepresentable)

fileprivate struct KeyboardMonitorView: NSViewRepresentable {
    let filteredItems: [ClipItem]
    @Binding var selectedItemID: UUID?
    let onSelect: (ClipItem) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = MonitorView()
        view.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Return nil (consume) for handled keys; return event (pass through) for others
            return context.coordinator.handleKeyEvent(event) ? nil : event
        }
        context.coordinator.owner = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.filteredItems = filteredItems
        context.coordinator.onSelect = onSelect
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(filteredItems: filteredItems, selectedItemID: $selectedItemID, onSelect: onSelect)
    }

    final class Coordinator {
        var filteredItems: [ClipItem]
        var selectedItemID: Binding<UUID?>
        var onSelect: (ClipItem) -> Void
        weak var owner: MonitorView?

        init(filteredItems: [ClipItem], selectedItemID: Binding<UUID?>, onSelect: @escaping (ClipItem) -> Void) {
            self.filteredItems = filteredItems
            self.selectedItemID = selectedItemID
            self.onSelect = onSelect
        }

        func handleKeyEvent(_ event: NSEvent) -> Bool {
            guard !filteredItems.isEmpty else { return false }
            let currentIndex: Int
            if let id = selectedItemID.wrappedValue,
               let idx = filteredItems.firstIndex(where: { $0.id == id }) {
                currentIndex = idx
            } else {
                // No selection yet — start at -1 so first ↓ selects index 0
                currentIndex = -1
            }

            switch event.keyCode {
            case 125: // ↓ (down arrow)
                let next = min(currentIndex + 1, filteredItems.count - 1)
                selectedItemID.wrappedValue = filteredItems[next].id
                return true
            case 126: // ↑ (up arrow)
                let prev = max(currentIndex - 1, 0)
                selectedItemID.wrappedValue = filteredItems[prev].id
                return true
            case 36, 76: // Enter (36 = Return, 76 = numpad Enter)
                if let id = selectedItemID.wrappedValue,
                   let item = filteredItems.first(where: { $0.id == id }) {
                    onSelect(item)
                }
                return true
            default:
                // Pass through: character input reaches search field
                return false
            }
        }
    }

    final class MonitorView: NSView {
        var monitor: Any?

        deinit {
            if let m = monitor {
                NSEvent.removeMonitor(m)
            }
        }
    }
}
```

- [ ] **Step 4: Reset selection when search text changes**

Add after the `filteredItems` computed property (around line 130-136):

```swift
    private var filteredItems: [ClipItem] {
        if searchText.isEmpty {
            return allItems
        }
        return allItems.filter { item in
            item.textContent?.localizedCaseInsensitiveContains(searchText) ?? false
        }
    }
```

Add an `.onChange` modifier to the `VStack` or to the search `TextField`:

Replace the existing `.onAppear` block we already edited:

```swift
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: searchText) { _, _ in
            // Reset selection to first item when filter changes
            selectedItemID = filteredItems.first?.id
        }
        .onDisappear {
            selectedItemID = nil
        }
```

- [ ] **Step 5: Pass `isSelected` and `isInteractive` to `ClipItemRow`**

Update the `ForEach` block (around line 56-66):

```swift
                    ForEach(filteredItems) { item in
                        ClipItemRow(
                            item: item,
                            isSelected: item.id == selectedItemID,
                            isInteractive: isExpandedReady,
                            onTap: { onItemTap(item) },
                            onDelete: { onItemDelete(item) }
                        )

                        Divider()
                            .padding(.leading, 12)
                    }
```

- [ ] **Step 6: Build to verify**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED** (ClipItemRow will error until Task 3 adds `isSelected` and `isInteractive` params)

- [ ] **Step 7: Commit**

```bash
git add "Mini Capsule/UI/CapsuleExpandedView.swift"
git commit -m "feat: add keyboard arrow-key navigation and readiness gating to expanded view

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Add selection highlight, interaction gating, and text preview to ClipItemRow

**Files:**
- Modify: `Mini Capsule/UI/ClipItemRow.swift`

**Interfaces:**
- Consumes: `isSelected: Bool`, `isInteractive: Bool` from CapsuleExpandedView (Task 2)
- Produces: Row highlight styling, hover/click gating, text popover preview

---

- [ ] **Step 1: Add `isSelected` and `isInteractive` parameters**

Replace the struct declaration (lines 4-7):

```swift
struct ClipItemRow: View {
    let item: ClipItem
    let isSelected: Bool
    let isInteractive: Bool
    var onTap: () -> Void
    var onDelete: () -> Void

    @State private var isHovering = false
```

- [ ] **Step 2: Add selection highlight and interaction gating to row**

Replace the row's `body` container styling — update the `.padding` and `.contentShape` section (lines 39-44) to include selection highlight before them:

Replace the entire `HStack` wrapper styling. The current HStack at line 12:

```swift
        HStack(spacing: 10) {
            typeIcon
                .frame(width: 36, height: 36)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(previewText)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(item.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onTap()
        }
```

Replace with:

```swift
        HStack(spacing: 10) {
            typeIcon
                .frame(width: 36, height: 36)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(previewText)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(item.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isHovering && isInteractive {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(selectionBackground)
        .contentShape(Rectangle())
        .onHover { hovering in
            guard isInteractive else { return }
            isHovering = hovering
        }
        .onTapGesture {
            guard isInteractive else { return }
            onTap()
        }
```

- [ ] **Step 3: Add `selectionBackground` computed property**

Add after the `body` closing `}` (before the image preview section):

```swift
    // MARK: - Selection

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.15))
                .padding(.horizontal, 4)
        }
    }
```

- [ ] **Step 4: Extend popover to include text preview**

Update the existing popover (lines 48-56) to include text. Replace the current:

```swift
        .popover(isPresented: Binding(
            get: { isHovering && item.contentTypeRaw == "image" },
            set: { isHovering = $0 }
        ), arrowEdge: .trailing) {
            if let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
                imagePreview(nsImage)
                    .padding(8)
            }
        }
```

Replace with:

```swift
        .popover(isPresented: Binding(
            get: { isHovering && (item.contentTypeRaw == "image" || item.contentTypeRaw == "text") },
            set: { isHovering = $0 }
        ), arrowEdge: .trailing) {
            if item.contentTypeRaw == "image",
               let imageData = item.imageData,
               let nsImage = NSImage(data: imageData) {
                imagePreview(nsImage)
                    .padding(8)
            } else if item.contentTypeRaw == "text",
                      let text = item.textContent {
                textPreview(text)
                    .padding(8)
            }
        }
```

- [ ] **Step 5: Add `textPreview` view**

Add after the `imagePreview` function (around line 80):

```swift
    // MARK: - Text Preview

    @ViewBuilder
    private func textPreview(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 300, maxHeight: 200)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
```

- [ ] **Step 6: Build to verify**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 7: Commit**

```bash
git add "Mini Capsule/UI/ClipItemRow.swift"
git commit -m "feat: add selection highlight, interaction gating, and text preview popover to ClipItemRow

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: End-to-end verification

- [ ] **Step 1: Run full build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 2: Manual verification checklist**
  - Expand capsule via hover → list items should be non-interactive during 0.35s animation
  - After animation, hover over a row → should highlight, show delete button, show preview popover
  - Press ↓ → selection highlight moves down, first press selects top item
  - Press ↑ → selection highlight moves up
  - Press Enter → selected item pastes
  - Type in search → list filters, selection resets to first item
  - Hover over text row → popover shows full text, scrollable
  - Hover over image row → popover still shows image preview (no regression)
  - Collapse capsule → items hide, re-expand works cleanly

- [ ] **Step 3: Run existing tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: tests pass

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: final verification after keyboard nav and text preview features

Co-Authored-By: Claude <noreply@anthropic.com>"
```
