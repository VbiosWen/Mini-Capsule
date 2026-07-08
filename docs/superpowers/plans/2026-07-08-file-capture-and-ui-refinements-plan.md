# File Capture & UI Refinements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship three usability fixes: (1) capture and display copied files (multi-file + system icon), (2) show first-character colored icon for text items, (3) make item clicks work on the first tap.

**Architecture:** All changes live in the existing `Mini Capsule` target — no SwiftData schema change. `fileBookmarks` is upgraded from a single bookmark `Data` to a JSON-encoded `[Data]` (with a legacy fallback on read). A deterministic hue helper on `Color` powers the text-item avatar. `ClipItemRow` gains a per-row cached resolved file URL for the NSWorkspace icon lookup.

**Tech Stack:** Swift 5, SwiftUI, SwiftData, AppKit (`NSWorkspace`, `NSPasteboard`), Swift Testing framework.

## Global Constraints

- Deployment target: macOS 26.5 (matches project).
- Use Swift Testing (`import Testing`, `@Test`, `#expect`) for unit tests. Do NOT introduce XCTest for unit tests.
- Do not add new SwiftData `@Model` fields — reuse `imageFileName` and `fileBookmarks`.
- Preserve backward compatibility for existing `fileBookmarks` blobs written before this change (single-bookmark `Data`).
- Do not change file paths or public APIs beyond what tasks explicitly specify.
- All tests must pass on macOS destination: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test`.

---

### Task 1: Deterministic color helper for text avatars

**Files:**
- Modify: `Mini Capsule/Utilities/ColorHex.swift`
- Test: `Mini CapsuleTests/ColorHexTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `extension Color { static func deterministic(from seed: String) -> Color }` — returns the same `Color` for the same seed, hue distributed across the full spectrum, saturation ∈ [0.55, 0.75], brightness ∈ [0.55, 0.70].

- [ ] **Step 1: Write the failing tests**

Append to `Mini CapsuleTests/ColorHexTests.swift`:

```swift
    @Test func deterministicColorIsStableForSameSeed() async throws {
        let a = Color.deterministic(from: "abc-123")
        let b = Color.deterministic(from: "abc-123")
        #expect(a.toHex() == b.toHex())
    }

    @Test func deterministicColorDiffersForDifferentSeeds() async throws {
        let a = Color.deterministic(from: "seed-A")
        let b = Color.deterministic(from: "seed-B")
        #expect(a.toHex() != b.toHex())
    }

    @Test func deterministicColorEmptySeedProducesValidColor() async throws {
        let color = Color.deterministic(from: "")
        let hex = color.toHex()
        #expect(hex.hasPrefix("#"))
        #expect(hex.count == 7)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:Mini_CapsuleTests/ColorHexTests test
```
Expected: FAIL — `deterministic(from:)` unknown.

- [ ] **Step 3: Add the helper**

Append to `Mini Capsule/Utilities/ColorHex.swift` (inside the existing `extension Color`):

```swift
    /// Deterministic color from a seed string. Same seed → same color.
    /// HSB tuned so both light and dark backgrounds show the color clearly.
    static func deterministic(from seed: String) -> Color {
        var hash: UInt64 = 0xcbf29ce484222325   // FNV-1a offset basis
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3           // FNV-1a prime
        }
        let hue = Double(hash & 0xFFFF) / 65535.0
        let sat = 0.55 + Double((hash >> 16) & 0xFFFF) / 65535.0 * 0.20
        let bri = 0.55 + Double((hash >> 32) & 0xFFFF) / 65535.0 * 0.15
        return Color(hue: hue, saturation: sat, brightness: bri)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:Mini_CapsuleTests/ColorHexTests test
```
Expected: PASS — all `ColorHexTests` including the three new ones.

- [ ] **Step 5: Commit**

```bash
git add "Mini Capsule/Utilities/ColorHex.swift" "Mini CapsuleTests/ColorHexTests.swift"
git commit -m "feat: deterministic color helper for text avatars"
```

---

### Task 2: First-character avatar for text items

**Files:**
- Modify: `Mini Capsule/UI/ClipItemRow.swift`

**Interfaces:**
- Consumes: `Color.deterministic(from:)` from Task 1.
- Produces: no exports (view-internal change).

- [ ] **Step 1: Replace the text branch of `typeIcon` and `iconForType`**

In `Mini Capsule/UI/ClipItemRow.swift`, find:

```swift
    @ViewBuilder
    private var typeIcon: some View {
        if item.contentTypeRaw == "image", let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
        } else {
            iconForType
                .font(.system(size: 15))
        }
    }

    private var iconForType: some View {
        switch item.contentTypeRaw {
        case "text": return Image(systemName: "doc.text")
        case "file": return Image(systemName: "doc")
        default: return Image(systemName: "questionmark")
        }
    }
```

Replace with:

```swift
    @ViewBuilder
    private var typeIcon: some View {
        if item.contentTypeRaw == "image", let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
        } else if item.contentTypeRaw == "text", let ch = firstDisplayCharacter(item.textContent) {
            Text(String(ch))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(Color.deterministic(from: item.id.uuidString))
                .frame(width: 36, height: 36)
        } else {
            iconForType
                .font(.system(size: 15))
        }
    }

    private func firstDisplayCharacter(_ text: String?) -> Character? {
        guard let text else { return nil }
        return text.first { !$0.isWhitespace && !$0.isNewline }
    }

    private var iconForType: some View {
        switch item.contentTypeRaw {
        case "text": return Image(systemName: "doc.text")
        case "file": return Image(systemName: "doc")
        default: return Image(systemName: "questionmark")
        }
    }
```

Note: `iconForType` keeps its `text` case as a fallback for empty-string items.

- [ ] **Step 2: Build to confirm no compile errors**

Run:
```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/UI/ClipItemRow.swift"
git commit -m "feat: first-character avatar with deterministic color for text items"
```

---

### Task 3: Single-click copy — remove `isInteractive` guard

**Files:**
- Modify: `Mini Capsule/UI/ClipItemRow.swift`

**Interfaces:** none.

- [ ] **Step 1: Remove the guard**

In `Mini Capsule/UI/ClipItemRow.swift`, find:

```swift
        .onTapGesture {
            guard isInteractive else { return }
            onTap()
        }
```

Replace with:

```swift
        .onTapGesture {
            onTap()
        }
```

(Do NOT remove the `isInteractive` property or its use for the hover delete-button visibility — only the tap guard.)

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/UI/ClipItemRow.swift"
git commit -m "fix: single-click copy in capsule (drop isInteractive tap guard)"
```

---

### Task 4: `ContentFilter.file` — add the File tab

**Files:**
- Modify: `Mini Capsule/UI/ClipboardListViewModel.swift`

**Interfaces:**
- Produces:
  - `ContentFilter.file` case (raw value `"文件"`, system image `"doc"`)
  - `filteredItems` filters `contentTypeRaw == "file"` when `.file` is selected

- [ ] **Step 1: Extend `ContentFilter`**

In `Mini Capsule/UI/ClipboardListViewModel.swift`, find:

```swift
enum ContentFilter: String, CaseIterable {
    case all = "全部"
    case text = "文本"
    case image = "图片"

    var systemImage: String {
        switch self {
        case .all: return "square.stack"
        case .text: return "doc.text"
        case .image: return "photo"
        }
    }
}
```

Replace with:

```swift
enum ContentFilter: String, CaseIterable {
    case all = "全部"
    case text = "文本"
    case image = "图片"
    case file = "文件"

    var systemImage: String {
        switch self {
        case .all: return "square.stack"
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
}
```

- [ ] **Step 2: Extend `filteredItems` filter switch**

In the same file, find:

```swift
        switch filterType {
        case .all:
            typeFiltered = allItems
        case .text:
            typeFiltered = allItems.filter { $0.contentTypeRaw == "text" }
        case .image:
            typeFiltered = allItems.filter { $0.contentTypeRaw == "image" }
        }
```

Replace with:

```swift
        switch filterType {
        case .all:
            typeFiltered = allItems
        case .text:
            typeFiltered = allItems.filter { $0.contentTypeRaw == "text" }
        case .image:
            typeFiltered = allItems.filter { $0.contentTypeRaw == "image" }
        case .file:
            typeFiltered = allItems.filter { $0.contentTypeRaw == "file" }
        }
```

- [ ] **Step 3: Build**

Run:
```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED. (The filter tabs UI iterates `ContentFilter.allCases`, so no separate view change is needed.)

- [ ] **Step 4: Commit**

```bash
git add "Mini Capsule/UI/ClipboardListViewModel.swift"
git commit -m "feat: add File filter tab to capsule list"
```

---

### Task 5: `PasteService.decodeFileBookmarks` — multi-bookmark decode with legacy fallback

**Files:**
- Modify: `Mini Capsule/Services/PasteService.swift`
- Test: `Mini CapsuleTests/PasteServiceTests.swift`

**Interfaces:**
- Produces:
  - `static func decodeFileBookmarks(_ data: Data) -> [Data]` — returns `[]` only for truly invalid input; on legacy single-bookmark bytes returns `[data]`.

- [ ] **Step 1: Write failing tests**

Append to `Mini CapsuleTests/PasteServiceTests.swift`:

```swift
    @Test func decodeFileBookmarksReturnsArrayForJSONEncodedBlob() throws {
        let bookmarks: [Data] = [Data([0x01, 0x02]), Data([0x03, 0x04, 0x05])]
        let encoded = try JSONEncoder().encode(bookmarks)
        let decoded = PasteService.decodeFileBookmarks(encoded)
        #expect(decoded.count == 2)
        #expect(decoded[0] == Data([0x01, 0x02]))
        #expect(decoded[1] == Data([0x03, 0x04, 0x05]))
    }

    @Test func decodeFileBookmarksLegacyBlobReturnsSingleElement() {
        // Legacy: raw bookmark Data written by old versions (not JSON).
        let legacy = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let decoded = PasteService.decodeFileBookmarks(legacy)
        #expect(decoded == [legacy])
    }

    @Test func decodeFileBookmarksEmptyJSONArrayFallsBackToLegacy() throws {
        // JSON `[]` is decodable but semantically empty — the safest read is
        // to treat the blob as legacy so we never silently drop content.
        let encoded = try JSONEncoder().encode([Data]())
        let decoded = PasteService.decodeFileBookmarks(encoded)
        #expect(decoded == [encoded])
    }
```

- [ ] **Step 2: Run tests to verify failure**

Run:
```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:Mini_CapsuleTests/PasteServiceTests test
```
Expected: FAIL — `decodeFileBookmarks` unknown.

- [ ] **Step 3: Add the helper to PasteService**

In `Mini Capsule/Services/PasteService.swift`, insert this method inside the `PasteService` class (before `paste`):

```swift
    /// Decode a `fileBookmarks` blob. New format is a JSON-encoded `[Data]`
    /// (one element per URL). Legacy blobs were a single raw bookmark
    /// `Data`; those are returned as `[data]` so old items still paste.
    static func decodeFileBookmarks(_ data: Data) -> [Data] {
        if let arr = try? JSONDecoder().decode([Data].self, from: data), !arr.isEmpty {
            return arr
        }
        return [data]
    }
```

- [ ] **Step 4: Update `copyToClipboard` file branch**

In `Mini Capsule/Services/PasteService.swift`, find:

```swift
        case "file":
            if let bookmarkData = item.fileBookmarks {
                var isStale = false
                if let url = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [],
                    bookmarkDataIsStale: &isStale
                ) {
                    pasteboard.writeObjects([url as NSURL])
                }
            }
        default:
            break
        }

        markSelfPaste()
    }

    static func paste(_ item: ClipItem, context: ModelContext) {
```

Replace **only the `case "file"` block inside `copyToClipboard`** (leave `paste` for the next step):

```swift
        case "file":
            if let bookmarkData = item.fileBookmarks {
                let bookmarks = Self.decodeFileBookmarks(bookmarkData)
                var isStale = false
                let urls: [URL] = bookmarks.compactMap {
                    try? URL(resolvingBookmarkData: $0, options: [], bookmarkDataIsStale: &isStale)
                }
                if !urls.isEmpty {
                    pasteboard.writeObjects(urls as [NSURL])
                }
            }
```

- [ ] **Step 5: Update `paste` file branch**

In the same file, inside the `paste(_:context:)` method, find:

```swift
        case "file":
            if let bookmarkData = item.fileBookmarks {
                var isStale = false
                if let url = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [],
                    bookmarkDataIsStale: &isStale
                ) {
                    pasteboard.writeObjects([url as NSURL])
                }
            }
        default: 
            break
        }
```

Replace with:

```swift
        case "file":
            if let bookmarkData = item.fileBookmarks {
                let bookmarks = Self.decodeFileBookmarks(bookmarkData)
                var isStale = false
                let urls: [URL] = bookmarks.compactMap {
                    try? URL(resolvingBookmarkData: $0, options: [], bookmarkDataIsStale: &isStale)
                }
                if !urls.isEmpty {
                    pasteboard.writeObjects(urls as [NSURL])
                }
            }
        default:
            break
        }
```

- [ ] **Step 6: Run tests to verify pass**

Run:
```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:Mini_CapsuleTests/PasteServiceTests test
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add "Mini Capsule/Services/PasteService.swift" "Mini CapsuleTests/PasteServiceTests.swift"
git commit -m "feat: multi-file bookmark decode + paste with legacy fallback"
```

---

### Task 6: `ClipboardMonitor` captures multi-file URLs + filename

**Files:**
- Modify: `Mini Capsule/Services/ClipboardMonitor.swift`
- Test: `Mini CapsuleTests/ClipboardMonitorTests.swift`

**Interfaces:**
- Consumes: `PasteService.decodeFileBookmarks` (indirectly, via Task 5) — not called here.
- Produces:
  - `static func encodeFileBookmarks(_ bookmarks: [Data]) -> Data?` — helper for tests and inline use.
  - The `fileBookmarks` value returned from the pasteboard `file` branch is now a JSON-encoded `[Data]`.
  - The `imageFileName` field on file-type `ClipItem`s is populated with the first URL's `lastPathComponent`.

- [ ] **Step 1: Write failing test**

Append to `Mini CapsuleTests/ClipboardMonitorTests.swift`:

```swift
    // MARK: - encodeFileBookmarks tests

    @Test func encodeFileBookmarksProducesJSONArrayRoundtripsThroughDecoder() throws {
        let raw: [Data] = [Data([0xAA, 0xBB]), Data([0xCC, 0xDD, 0xEE])]
        guard let encoded = ClipboardMonitor.encodeFileBookmarks(raw) else {
            Issue.record("encode returned nil")
            return
        }
        let roundtripped = try JSONDecoder().decode([Data].self, from: encoded)
        #expect(roundtripped == raw)
    }

    @Test func encodeFileBookmarksEmptyReturnsNil() {
        let encoded = ClipboardMonitor.encodeFileBookmarks([])
        #expect(encoded == nil)
    }
```

- [ ] **Step 2: Run test to verify failure**

Run:
```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:Mini_CapsuleTests/ClipboardMonitorTests test
```
Expected: FAIL — `encodeFileBookmarks` unknown.

- [ ] **Step 3: Add `encodeFileBookmarks` helper**

In `Mini Capsule/Services/ClipboardMonitor.swift`, add this static method next to `md5Hash`:

```swift
    /// Encode `[Data]` bookmarks as JSON for the `fileBookmarks` field.
    /// Returns nil for an empty array so callers can early-out cleanly.
    static func encodeFileBookmarks(_ bookmarks: [Data]) -> Data? {
        guard !bookmarks.isEmpty else { return nil }
        return try? JSONEncoder().encode(bookmarks)
    }
```

- [ ] **Step 4: Replace the file branch in `readPasteboard`**

In `Mini Capsule/Services/ClipboardMonitor.swift`, find:

```swift
        // 3. fileURL
        if types.contains(.fileURL),
           let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first {
            let bookmarks = try? firstURL.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return ("file", nil, nil, bookmarks, nil)
        }
```

Replace with:

```swift
        // 3. fileURL — capture every URL on the pasteboard as its own bookmark.
        if types.contains(.fileURL),
           let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            let bookmarks: [Data] = urls.compactMap {
                try? $0.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            }
            guard let encoded = Self.encodeFileBookmarks(bookmarks) else { return nil }
            let firstName = urls.first?.lastPathComponent
            return ("file", nil, nil, encoded, firstName)
        }
```

- [ ] **Step 5: Persist filename for file items in `checkPasteboard`**

In the same file, find:

```swift
        let item = ClipItem(
            timestamp: Date(),
            contentTypeRaw: content.type,
            textContent: content.text,
            fileBookmarks: content.fileBookmarks,
            sourceAppBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        context.insert(item)
        try? context.save()
    }
```

Replace with:

```swift
        let item = ClipItem(
            timestamp: Date(),
            contentTypeRaw: content.type,
            textContent: content.text,
            imageFileName: content.type == "file" ? content.fileName : nil,
            fileBookmarks: content.fileBookmarks,
            sourceAppBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        context.insert(item)
        try? context.save()
    }
```

- [ ] **Step 6: Run tests to verify pass**

Run:
```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:Mini_CapsuleTests/ClipboardMonitorTests test
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add "Mini Capsule/Services/ClipboardMonitor.swift" "Mini CapsuleTests/ClipboardMonitorTests.swift"
git commit -m "feat: capture all pasteboard file URLs + filename for file items"
```

---

### Task 7: File-item UI — system icon, filename preview, multi-file suffix

**Files:**
- Modify: `Mini Capsule/UI/ClipItemRow.swift`

**Interfaces:**
- Consumes: `PasteService.decodeFileBookmarks` (Task 5), `ClipItem.imageFileName` / `.fileBookmarks` populated by Task 6.

- [ ] **Step 1: Add file-icon resolution state**

In `Mini Capsule/UI/ClipItemRow.swift`, find the `@State` declarations:

```swift
    @State private var isHovering = false
    @State private var showPopover = false
    @State private var showEditor = false
    @State private var isPopoverHovered = false
    @State private var hoverTask: Task<Void, Never>?
```

Append two new state properties:

```swift
    @State private var resolvedFileURL: URL?
    @State private var resolvedFileCount: Int = 0
```

- [ ] **Step 2: Resolve the first file URL when the row appears**

Find the `body` property — the `HStack(spacing: 10)` root. Just before `.onHover { hovering in`, add:

```swift
        .task(id: item.id) {
            guard item.contentTypeRaw == "file",
                  let blob = item.fileBookmarks else {
                resolvedFileURL = nil
                resolvedFileCount = 0
                return
            }
            let bookmarks = PasteService.decodeFileBookmarks(blob)
            resolvedFileCount = bookmarks.count
            var isStale = false
            resolvedFileURL = bookmarks.first.flatMap {
                try? URL(resolvingBookmarkData: $0, options: [], bookmarkDataIsStale: &isStale)
            }
        }
```

- [ ] **Step 3: Show the system icon for file items in `typeIcon`**

Find the `typeIcon` view (the one Task 2 already updated) and update the `else if` chain. Replace:

```swift
    @ViewBuilder
    private var typeIcon: some View {
        if item.contentTypeRaw == "image", let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
        } else if item.contentTypeRaw == "text", let ch = firstDisplayCharacter(item.textContent) {
            Text(String(ch))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(Color.deterministic(from: item.id.uuidString))
                .frame(width: 36, height: 36)
        } else {
            iconForType
                .font(.system(size: 15))
        }
    }
```

with:

```swift
    @ViewBuilder
    private var typeIcon: some View {
        if item.contentTypeRaw == "image", let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
        } else if item.contentTypeRaw == "text", let ch = firstDisplayCharacter(item.textContent) {
            Text(String(ch))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(Color.deterministic(from: item.id.uuidString))
                .frame(width: 36, height: 36)
        } else if item.contentTypeRaw == "file", let url = resolvedFileURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
        } else {
            iconForType
                .font(.system(size: 15))
        }
    }
```

- [ ] **Step 4: Update `previewText` for files (filename + " 等 N 项" for multi)**

Find `previewText`:

```swift
    private var previewText: String {
        switch item.contentTypeRaw {
        case "text":
            return item.textContent?.prefix(50).replacingOccurrences(of: "\n", with: " ") ?? ""
        case "image":
            return item.imageFileName ?? "图片"
        case "file":
            return "文件"
        default:
            return "未知"
        }
    }
```

Replace the `case "file"` branch:

```swift
    private var previewText: String {
        switch item.contentTypeRaw {
        case "text":
            return item.textContent?.prefix(50).replacingOccurrences(of: "\n", with: " ") ?? ""
        case "image":
            return item.imageFileName ?? "图片"
        case "file":
            let name = item.imageFileName ?? "文件"
            return resolvedFileCount > 1 ? "\(name) 等 \(resolvedFileCount) 项" : name
        default:
            return "未知"
        }
    }
```

- [ ] **Step 5: Add `import AppKit` if missing**

At the top of `Mini Capsule/UI/ClipItemRow.swift`, confirm `import SwiftUI` is present and add `import AppKit` immediately after if it isn't. (Needed for `NSWorkspace`.)

Verify with:
```bash
head -5 "Mini Capsule/UI/ClipItemRow.swift"
```

If AppKit is not imported, add it as the second line.

- [ ] **Step 6: Build**

Run:
```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add "Mini Capsule/UI/ClipItemRow.swift"
git commit -m "feat: system icon + filename preview for file items in capsule list"
```

---

### Task 8: `CapsuleCollapsedView` shows filename for file items

**Files:**
- Modify: `Mini Capsule/UI/CapsuleCollapsedView.swift`

**Interfaces:** consumes `ClipItem.imageFileName`.

- [ ] **Step 1: Update `summaryText`**

In `Mini Capsule/UI/CapsuleCollapsedView.swift`, find:

```swift
    private var summaryText: String {
        guard let item = latestItem else { return "等待复制..." }
        switch item.contentTypeRaw {
        case "text":
            return item.textContent?.prefix(20).replacingOccurrences(of: "\n", with: " ") ?? ""
        case "image":
            return "🖼️ 图片"
        case "file":
            return "📁 文件"
        default:
            return ""
        }
    }
```

Replace with:

```swift
    private var summaryText: String {
        guard let item = latestItem else { return "等待复制..." }
        switch item.contentTypeRaw {
        case "text":
            return item.textContent?.prefix(20).replacingOccurrences(of: "\n", with: " ") ?? ""
        case "image":
            return "🖼️ 图片"
        case "file":
            return "📁 \(item.imageFileName ?? "文件")"
        default:
            return ""
        }
    }
```

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/UI/CapsuleCollapsedView.swift"
git commit -m "feat: collapsed capsule shows filename for file items"
```

---

### Task 9: Full test + build verification

**Files:** none modified — verification only.

- [ ] **Step 1: Run the full test suite**

Run:
```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test
```
Expected: TEST SUCCEEDED. All Swift Testing suites pass, including new tests in Tasks 1, 5, 6.

- [ ] **Step 2: Confirm no uncommitted work**

Run:
```bash
git status --short
```
Expected: only pre-existing unrelated files (`CLAUDE.md`, `Development.entitlements`, etc. that existed before this plan) — no modified files from this plan.

- [ ] **Step 3: Note anything the automated tests can't cover**

Manual verification checklist (report to user, do not commit):

- Copy a single file from Finder → capsule expands → row shows filename + system icon → single-click copies.
- Copy multiple files from Finder → row shows `firstname 等 N 项` and system icon of the first.
- Copy a text snippet → row shows first character in a colored circle; same item across restarts shows same color.
- Existing file items from before this change (if any) still paste correctly (legacy fallback).
- File filter tab shows only file items.
