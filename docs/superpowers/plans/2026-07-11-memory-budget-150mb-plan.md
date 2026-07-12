# Memory Budget 150 MB Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep Mini Capsule RSS ≤ 150 MB under realistic workloads (100+ image items), without changing user-configurable limits or removing features.

**Architecture:** SwiftData `@Attribute(.externalStorage)` on `imageData` + new `imageThumbnail` blob column so list rows read tiny thumbnails and full images stay unloaded until popover. `ClipboardListViewModel.filteredItems` becomes a memoized cache invalidated via `.clipItemsDidChange` notification. All NSImage/NSBitmapImageRep churn wrapped in `autoreleasepool`. Legacy image items backfill thumbnails lazily on scroll.

**Tech Stack:** SwiftUI, SwiftData, AppKit, Swift Testing (`@Test`/`#expect`).

## Global Constraints

- macOS deployment target 26.5; no APIs from newer SDKs.
- Do NOT change defaults of `SettingsData.imageMaxSizeMB` (2) or `historyMaxCount` (200).
- Do NOT remove background image feature (`SettingsData.backgroundImageData`).
- Do NOT add total-bytes hard budget or debug memory HUD — out of scope per spec.
- Swift uses ARC, not GC — "fast reclamation" means `autoreleasepool` around large temporary allocations and clearing strong refs promptly.
- SwiftData `@Model` writes must go through the `ModelContext` on the main actor.
- Existing `@ObservationIgnored` pattern applies to internal caches so the tracked graph doesn't include them.
- Test target: `Mini CapsuleTests` (Swift Testing). Existing pattern uses `@MainActor struct XxxTests { @Test func … }` and a private `MockSettings: SettingsProtocol`.
- Build command (no signing): `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`.
- Test command (append after above): `test`.

---

### Task 1: Notification + Model additions

**Files:**
- Modify: `Mini Capsule/Settings/NotificationNames.swift` (append one line inside the second `extension Notification.Name` block)
- Modify: `Mini Capsule/Models/ClipItem.swift:13-49`

**Interfaces:**
- Consumes: nothing (foundation)
- Produces:
  - `Notification.Name.clipItemsDidChange` (posted by ClipboardMonitor after inserts, consumed by ClipboardListViewModel)
  - `ClipItem.imageData` now uses `@Attribute(.externalStorage)`
  - `ClipItem.imageThumbnail: Data?` — externally stored PNG blob (~2–5 KB) for row rendering
  - `ClipItem.init` gains `imageThumbnail: Data? = nil` parameter (default keeps existing call sites compiling)

- [ ] **Step 1: Add the notification**

Edit `Mini Capsule/Settings/NotificationNames.swift` — inside the `// MARK: - Capsule Notifications` extension block, after `shortcutsDidChange`, add:

```swift
    /// Posted after ClipboardMonitor inserts or mutates ClipItem records.
    /// Consumers (ClipboardListViewModel) use this to invalidate cached fetch results.
    static let clipItemsDidChange = Notification.Name("clipItemsDidChange")
```

- [ ] **Step 2: Update ClipItem model**

Replace `Mini Capsule/Models/ClipItem.swift` in full:

```swift
// Mini Capsule/Models/ClipItem.swift
import Foundation
import SwiftData

@Model
final class ClipItem {
    var id: UUID
    var timestamp: Date
    var lastPastedAt: Date?
    var pasteCount: Int
    var contentTypeRaw: String
    var textContent: String?
    @Attribute(.externalStorage) var imageData: Data?
    @Attribute(.externalStorage) var imageThumbnail: Data?
    var imageFileName: String?
    var imageMD5: String?
    var fileBookmarks: Data?
    var isPinned: Bool
    var sortOrder: Int?  // non-nil for pinned items, nil for unpinned
    var sourceAppBundleID: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        lastPastedAt: Date? = nil,
        pasteCount: Int = 0,
        contentTypeRaw: String,
        textContent: String? = nil,
        imageData: Data? = nil,
        imageThumbnail: Data? = nil,
        imageFileName: String? = nil,
        imageMD5: String? = nil,
        fileBookmarks: Data? = nil,
        isPinned: Bool = false,
        sortOrder: Int? = nil,
        sourceAppBundleID: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.lastPastedAt = lastPastedAt
        self.pasteCount = pasteCount
        self.contentTypeRaw = contentTypeRaw
        self.textContent = textContent
        self.imageData = imageData
        self.imageThumbnail = imageThumbnail
        self.imageFileName = imageFileName
        self.imageMD5 = imageMD5
        self.fileBookmarks = fileBookmarks
        self.isPinned = isPinned
        self.sortOrder = sortOrder
        self.sourceAppBundleID = sourceAppBundleID
    }
}
```

- [ ] **Step 3: Build to confirm schema change compiles and other files still call the init positionally-compatible**

Run:
```
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`. Existing call sites (ClipboardMonitor, tests) use labeled arguments so the new `imageThumbnail:` default keeps them compiling.

- [ ] **Step 4: Commit**

```
git add "Mini Capsule/Settings/NotificationNames.swift" "Mini Capsule/Models/ClipItem.swift"
git commit -m "feat(model): add imageThumbnail column + external storage for imageData

Prepares memory-budget work: full images are lazy-loaded from external
files, list rows will read the new small thumbnail column instead.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 2: `generateThumbnail` helper (TDD)

**Files:**
- Modify: `Mini Capsule/Services/ClipboardMonitor.swift` (add one static method near the other image helpers around line 232)
- Modify: `Mini CapsuleTests/ClipboardMonitorTests.swift` (append two tests before the closing `}` of the `ClipboardMonitorTests` struct)

**Interfaces:**
- Consumes: `ClipItem.imageThumbnail` (from Task 1)
- Produces: `static func ClipboardMonitor.generateThumbnail(_ data: Data, maxDimension: CGFloat = 72) -> Data?` — returns PNG data whose longest side ≤ `maxDimension`; returns `nil` for undecodable input. Wrapped in `autoreleasepool` internally.

- [ ] **Step 1: Add failing tests**

Append to `Mini CapsuleTests/ClipboardMonitorTests.swift` before the closing `}` of `struct ClipboardMonitorTests`:

```swift
    // MARK: - generateThumbnail tests

    @Test func generateThumbnailProducesPNGUnderMaxDimension() {
        // Build a 200×300 red image and encode as PNG.
        let original = NSImage(size: NSSize(width: 200, height: 300))
        original.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: NSSize(width: 200, height: 300)).fill()
        original.unlockFocus()
        let monitor = ClipboardMonitor(settings: MockSettings())
        let pngData = monitor.nsImageToPNGData(original)

        let thumb = ClipboardMonitor.generateThumbnail(pngData, maxDimension: 72)

        #expect(thumb != nil, "thumbnail should be generated for valid image")
        guard let thumb, let decoded = NSImage(data: thumb) else {
            Issue.record("thumb undecodable")
            return
        }
        #expect(max(decoded.size.width, decoded.size.height) <= 72,
                "longest side must be ≤ maxDimension")
        // Verify PNG signature
        let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        #expect(Array(thumb.prefix(8)) == pngSignature)
    }

    @Test func generateThumbnailReturnsNilForGarbageData() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])
        #expect(ClipboardMonitor.generateThumbnail(garbage) == nil)
    }
```

- [ ] **Step 2: Run tests to see them fail**

Run:
```
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "generateThumbnail|error:" | head -10
```
Expected: compile error like `Type 'ClipboardMonitor' has no member 'generateThumbnail'`.

- [ ] **Step 3: Implement `generateThumbnail`**

Insert into `Mini Capsule/Services/ClipboardMonitor.swift` right after the `nsImageToPNGData` method (around line 243). Preserve existing indentation (4 spaces):

```swift
    /// Decode `data`, redraw at `maxDimension` (longest side), and return PNG bytes.
    /// Used at capture time for the row-preview thumbnail column, and lazily by
    /// legacy items on first render. Wrapped in `autoreleasepool` so the transient
    /// NSImage / NSBitmapImageRep drop as soon as this returns.
    static func generateThumbnail(_ data: Data, maxDimension: CGFloat = 72) -> Data? {
        autoreleasepool {
            guard let source = NSImage(data: data) else { return nil }
            let src = source.size
            guard src.width > 0, src.height > 0 else { return nil }
            let longest = max(src.width, src.height)
            let scale = min(1.0, maxDimension / longest)
            let target = NSSize(width: src.width * scale, height: src.height * scale)

            let out = NSImage(size: target)
            out.lockFocus()
            source.draw(in: NSRect(origin: .zero, size: target),
                        from: NSRect(origin: .zero, size: src),
                        operation: .copy, fraction: 1.0)
            out.unlockFocus()

            guard let tiff = out.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:])
            else { return nil }
            return png
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run same test command as Step 2 but grep for pass state:
```
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO test 2>&1 | grep -E "generateThumbnail|TEST"
```
Expected: both new tests pass; overall `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```
git add "Mini Capsule/Services/ClipboardMonitor.swift" "Mini CapsuleTests/ClipboardMonitorTests.swift"
git commit -m "feat(monitor): add generateThumbnail helper

Static PNG thumbnail generator wrapped in autoreleasepool. Used at
capture time and by row lazy backfill.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 3: Monitor integration — autoreleasepool wrapping, thumbnail on insert, notification

**Files:**
- Modify: `Mini Capsule/Services/ClipboardMonitor.swift:71-164` (checkPasteboard image insert paths + text/file insert path) and `:236-243, :266-285` (autoreleasepool wrap of `nsImageToPNGData` and `capImageSize`)

**Interfaces:**
- Consumes: `ClipItem.imageThumbnail` (from Task 1), `ClipboardMonitor.generateThumbnail` (from Task 2), `Notification.Name.clipItemsDidChange` (from Task 1)
- Produces: every image insert now writes an `imageThumbnail`; every save posts `.clipItemsDidChange`

- [ ] **Step 1: Wrap existing image helpers in autoreleasepool**

In `nsImageToPNGData` (currently lines ~236–243), change the body to:

```swift
    func nsImageToPNGData(_ nsImage: NSImage) -> Data {
        autoreleasepool {
            let tiff = nsImage.tiffRepresentation
            guard let tiff,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:])
            else { return tiff ?? Data() }
            return png
        }
    }
```

In `capImageSize` (currently lines ~266–285), change the body to:

```swift
    private func capImageSize(_ data: Data, maxBytes: Int) -> Data {
        autoreleasepool {
            guard data.count > maxBytes,
                  let image = NSImage(data: data) else { return data }
            let scale = sqrt(Double(maxBytes) / Double(data.count))
            let newSize = NSSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            let resized = NSImage(size: newSize)
            resized.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: newSize),
                       from: NSRect(origin: .zero, size: image.size),
                       operation: .copy, fraction: 1.0)
            resized.unlockFocus()
            guard let tiff = resized.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
            else { return data }
            return jpeg
        }
    }
```

- [ ] **Step 2: Add thumbnail generation + notification post to `checkPasteboard`**

In `checkPasteboard` (around lines 71–164), the image branch currently constructs `ClipItem(...)` in two places (dedup enabled path around line 104 and no-dedup path around line 121), and the fall-through text/file path at line 154. Do these edits:

**Dedup-enabled image insert (around line 100–113)** — replace the block starting at `let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier` (inside the `if isDedupEnabled { ... }` branch of the image block) through the `try? context.save()` and `return`, with:

```swift
                let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                let appName = NSWorkspace.shared.frontmostApplication?.localizedName
                let fileName = content.fileName ?? "\(appName ?? "未知")-\(UUID().uuidString.prefix(4))"
                let thumbnail = Self.generateThumbnail(imageData)

                let item = ClipItem(
                    timestamp: Date(),
                    contentTypeRaw: content.type,
                    imageData: imageData,
                    imageThumbnail: thumbnail,
                    imageFileName: fileName,
                    imageMD5: md5,
                    sourceAppBundleID: sourceApp
                )
                context.insert(item)
                try? context.save()
                NotificationCenter.default.post(name: .clipItemsDidChange, object: nil)
                return
```

**Non-dedup image insert (around line 116–131)** — replace similarly with:

```swift
            } else {
                // No dedup — always insert
                Self.enforceCap(context: context, maxCount: maxHistoryCount)
                let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                let appName = NSWorkspace.shared.frontmostApplication?.localizedName
                let fileName = content.fileName ?? "\(appName ?? "未知")-\(UUID().uuidString.prefix(4))"
                let thumbnail = Self.generateThumbnail(imageData)
                let item = ClipItem(
                    timestamp: Date(),
                    contentTypeRaw: content.type,
                    imageData: imageData,
                    imageThumbnail: thumbnail,
                    imageFileName: fileName,
                    imageMD5: Self.md5Hash(imageData),
                    sourceAppBundleID: sourceApp
                )
                context.insert(item)
                try? context.save()
                NotificationCenter.default.post(name: .clipItemsDidChange, object: nil)
                return
            }
```

**Fall-through insert (around line 152–164)** — the text/file path. After the existing `try? context.save()` on line 163, add:

```swift
        NotificationCenter.default.post(name: .clipItemsDidChange, object: nil)
```

Also, in the dedup dedup-hit early return (around line 92–95) — the `existingItem.timestamp = Date()` + `try? context.save()` case — add the same post right after `try? context.save()`:

```swift
                if let existingItem = existing?.first {
                    existingItem.timestamp = Date()
                    try? context.save()
                    NotificationCenter.default.post(name: .clipItemsDidChange, object: nil)
                    return
                }
```

And the text-dedup hit around line 141–144 (`latest.timestamp = Date()` + `try? context.save()`) — same addition:

```swift
                case ("text", "text") where latest.textContent == content.text:
                    latest.timestamp = Date()
                    try? context.save()
                    NotificationCenter.default.post(name: .clipItemsDidChange, object: nil)
                    return
```

- [ ] **Step 3: Build**

Run the build command from Global Constraints. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run existing tests to confirm nothing regressed**

Run the test command. Expected: all previously-passing tests still pass (93+ tests including the two from Task 2). No new tests added in this task — behavior tests come in Task 4 (VM cache invalidation).

- [ ] **Step 5: Commit**

```
git add "Mini Capsule/Services/ClipboardMonitor.swift"
git commit -m "feat(monitor): write imageThumbnail on capture + post .clipItemsDidChange

Also wraps existing image processing helpers in autoreleasepool so
transient NSImage / NSBitmapImageRep release immediately.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 4: VM cached `filteredItems` + notification-driven invalidation (TDD)

**Files:**
- Modify: `Mini Capsule/UI/ClipboardListViewModel.swift` in full (rewrite)
- Modify: `Mini CapsuleTests/ClipboardListViewModelTests.swift` — append two new tests

**Interfaces:**
- Consumes: `Notification.Name.clipItemsDidChange` (from Task 1)
- Produces:
  - `ClipboardListViewModel.filteredItems: [ClipItem]` — same shape as before, now memoized on `(searchText, filterType, cacheVersion)`
  - `ClipboardListViewModel.invalidateCache()` — bumps cacheVersion, clears storage; called internally on every write op and by the notification observer
  - `ClipboardListViewModel.purgeCache()` — clears storage only, does not bump version (used by WindowController on collapse in Task 6)

- [ ] **Step 1: Read the existing test file to preserve its patterns**

Run: `wc -l "Mini CapsuleTests/ClipboardListViewModelTests.swift"` to see length, then read fully so you match style.

- [ ] **Step 2: Add failing tests**

Append these two tests to `Mini CapsuleTests/ClipboardListViewModelTests.swift` before the closing `}` of the test struct (or add a new suite if the file uses multiple `@Suite` groupings). If a `MockSettings` conforming to `SettingsProtocol` is not already private in that file, add one at the top matching the shape used in `ClipboardMonitorTests.swift`.

```swift
    @Test func filteredItemsCachesResultWhileKeyUnchanged() throws {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        for i in 0..<5 {
            context.insert(ClipItem(contentTypeRaw: "text", textContent: "t\(i)"))
        }
        try context.save()

        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)
        let first = vm.filteredItems
        let second = vm.filteredItems

        // Same array identity implies cache hit (no re-fetch, same instances).
        #expect(first.count == 5)
        #expect(second.count == 5)
        #expect(first.map(\.id) == second.map(\.id))
    }

    @Test func invalidateOnClipItemsDidChangeNotification() throws {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        context.insert(ClipItem(contentTypeRaw: "text", textContent: "before"))
        try context.save()

        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)
        _ = vm.filteredItems  // populate cache

        context.insert(ClipItem(contentTypeRaw: "text", textContent: "after"))
        try context.save()
        NotificationCenter.default.post(name: .clipItemsDidChange, object: nil)

        // After notification, next access must reflect the new item.
        #expect(vm.filteredItems.count == 2)
    }
```

- [ ] **Step 3: Rewrite the first test to fail meaningfully via a testing SPI**

The `filteredItemsCachesResultWhileKeyUnchanged` shape above tests behavior that a
non-caching implementation would still satisfy (both fetches return the same
items). Replace it with a stronger test that observes the cache's internal
size via a new testing SPI — this test will genuinely fail before the
implementation lands. Replace the first test with:

```swift
    @Test func filteredItemsCachePopulatesAfterFirstRead() throws {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        context.insert(ClipItem(contentTypeRaw: "text", textContent: "x"))
        try context.save()

        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)
        #expect(vm._cachedItemCountForTesting == 0)  // cold
        _ = vm.filteredItems
        #expect(vm._cachedItemCountForTesting == 1)  // warm
        vm.invalidateCache()
        #expect(vm._cachedItemCountForTesting == 0)  // invalidated
    }
```

This uses a testing SPI `_cachedItemCountForTesting` which is added in Step 4.

Run test command. Expected: compile error `Value of type 'ClipboardListViewModel' has no member '_cachedItemCountForTesting'` — proves the SPI + logic don't exist.

- [ ] **Step 4: Rewrite `ClipboardListViewModel` with cache + invalidation**

Replace the file `Mini Capsule/UI/ClipboardListViewModel.swift` in full:

```swift
// Mini Capsule/UI/ClipboardListViewModel.swift
import SwiftUI
import SwiftData
import AppKit

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

@MainActor
@Observable
final class ClipboardListViewModel {
    // MARK: - Filter State (observed)

    var searchText = ""
    var filterType: ContentFilter = .all

    // MARK: - Selection State (observed)

    var selectedItemIDs = Set<UUID>()
    var isMultiSelectMode = false
    var lastCopiedItemID: UUID?

    // MARK: - Cache Version (observed)
    /// Tracked so SwiftUI re-renders when we invalidate. Consumers read
    /// `filteredItems` which reads this transitively.
    private var cacheVersion: Int = 0

    // MARK: - Dependencies

    let modelContext: ModelContext
    let settings: SettingsStore

    // MARK: - Cache Storage (not observed)

    @ObservationIgnored private var itemsCache: [ClipItem] = []
    @ObservationIgnored private var cacheKey: CacheKey?
    @ObservationIgnored private var changeObserver: NSObjectProtocol?

    private struct CacheKey: Equatable {
        let search: String
        let filter: ContentFilter
        let version: Int
    }

    // MARK: - Init / Deinit

    init(modelContext: ModelContext, settings: SettingsStore) {
        self.modelContext = modelContext
        self.settings = settings
        self.changeObserver = NotificationCenter.default.addObserver(
            forName: .clipItemsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.invalidateCache() }
        }
    }

    deinit {
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Cache Control

    func invalidateCache() {
        cacheVersion &+= 1
        cacheKey = nil
        itemsCache = []
    }

    /// Clear the strong ref array without bumping version. Called on capsule
    /// collapse so SwiftData can release the managed objects.
    func purgeCache() {
        cacheKey = nil
        itemsCache = []
    }

    /// Testing SPI — how many ClipItems the cache currently retains.
    var _cachedItemCountForTesting: Int { itemsCache.count }

    // MARK: - Computed

    /// Fetch all items, sorted by pinned-first then timestamp descending.
    /// Pinned items sorted by sortOrder (ascending), unpinned by timestamp.
    /// Memoized on (searchText, filterType, cacheVersion).
    var filteredItems: [ClipItem] {
        let key = CacheKey(search: searchText, filter: filterType, version: cacheVersion)
        if key == cacheKey { return itemsCache }

        let descriptor = FetchDescriptor<ClipItem>(
            sortBy: [SortDescriptor(\ClipItem.timestamp, order: .reverse)]
        )
        let allItems = (try? modelContext.fetch(descriptor)) ?? []

        let typeFiltered: [ClipItem]
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

        let searched: [ClipItem]
        if searchText.isEmpty {
            searched = typeFiltered
        } else {
            searched = typeFiltered.filter { item in
                item.textContent?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }

        let result = searched.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            if a.isPinned {
                return (a.sortOrder ?? Int.max) < (b.sortOrder ?? Int.max)
            }
            return a.timestamp > b.timestamp
        }
        cacheKey = key
        itemsCache = result
        return result
    }

    var pinnedCount: Int {
        let descriptor = FetchDescriptor<ClipItem>(sortBy: [])
        let allItems = (try? modelContext.fetch(descriptor)) ?? []
        return allItems.filter(\.isPinned).count
    }

    var totalCount: Int {
        (try? modelContext.fetchCount(FetchDescriptor<ClipItem>())) ?? 0
    }

    // MARK: - Actions

    func copyItem(_ item: ClipItem) {
        PasteService.copyToClipboard(item)
        item.pasteCount += 1
        item.lastPastedAt = Date()
        item.timestamp = Date()
        try? modelContext.save()
        lastCopiedItemID = item.id
        invalidateCache()
    }

    func pasteItem(_ item: ClipItem) {
        PasteService.paste(item, context: modelContext)
        invalidateCache()
    }

    func deleteItem(_ item: ClipItem) {
        if let idx = selectedItemIDs.firstIndex(of: item.id) {
            selectedItemIDs.remove(at: idx)
        }
        modelContext.delete(item)
        try? modelContext.save()
        invalidateCache()
    }

    func deleteSelected() {
        guard isMultiSelectMode, !selectedItemIDs.isEmpty else { return }
        let descriptor = FetchDescriptor<ClipItem>(sortBy: [])
        guard let items = try? modelContext.fetch(descriptor) else { return }
        for item in items where selectedItemIDs.contains(item.id) {
            modelContext.delete(item)
        }
        try? modelContext.save()
        selectedItemIDs.removeAll()
        isMultiSelectMode = false
        invalidateCache()
    }

    func togglePin(_ item: ClipItem) {
        item.isPinned.toggle()
        if item.isPinned {
            let pinned = (try? modelContext.fetch(FetchDescriptor<ClipItem>(sortBy: [])))?.filter(\.isPinned) ?? []
            item.sortOrder = (pinned.map { $0.sortOrder ?? 0 }.max() ?? -1) + 1
        } else {
            item.sortOrder = nil
        }
        try? modelContext.save()
        invalidateCache()
    }

    func editText(_ item: ClipItem, content: String) {
        item.textContent = content
        try? modelContext.save()
        invalidateCache()
    }

    func toggleMultiSelect() {
        isMultiSelectMode.toggle()
        if !isMultiSelectMode {
            selectedItemIDs.removeAll()
        }
    }

    // MARK: - Keyboard Navigation

    func moveSelectionUp() {
        let items = filteredItems
        guard !items.isEmpty else { return }
        guard let currentID = selectedItemIDs.first,
              let idx = items.firstIndex(where: { $0.id == currentID }) else {
            selectedItemIDs = [items[0].id]
            return
        }
        let prev = max(idx - 1, 0)
        selectedItemIDs = [items[prev].id]
    }

    func moveSelectionDown() {
        let items = filteredItems
        guard !items.isEmpty else { return }
        guard let currentID = selectedItemIDs.first,
              let idx = items.firstIndex(where: { $0.id == currentID }) else {
            selectedItemIDs = [items[0].id]
            return
        }
        let next = min(idx + 1, items.count - 1)
        selectedItemIDs = [items[next].id]
    }

    func confirmSelection() {
        guard let selectedID = selectedItemIDs.first,
              let item = filteredItems.first(where: { $0.id == selectedID }) else { return }
        copyItem(item)
    }

    func handleEscape() {
        if !searchText.isEmpty {
            searchText = ""
        } else if isMultiSelectMode {
            toggleMultiSelect()
        }
    }

    func selectAll() {
        selectedItemIDs = Set(filteredItems.map(\.id))
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run the test command. Expected: the two new tests pass; all previously-passing tests still pass.

- [ ] **Step 6: Commit**

```
git add "Mini Capsule/UI/ClipboardListViewModel.swift" "Mini CapsuleTests/ClipboardListViewModelTests.swift"
git commit -m "feat(vm): memoize filteredItems, invalidate on .clipItemsDidChange

Adds keyed cache to avoid re-fetching all ClipItems on every SwiftUI
re-render. Invalidated by every write op and by external notification
so ClipboardMonitor inserts propagate. Adds purgeCache() for the
capsule collapse hook (used in a later task).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 5: Row uses thumbnail + lazy backfill for legacy items

**Files:**
- Modify: `Mini Capsule/UI/ClipItemRow.swift` — `typeIcon` (around lines 251–272), `.task(id: item.id)` (around lines 66–79)

**Interfaces:**
- Consumes: `ClipItem.imageThumbnail` (Task 1), `ClipboardMonitor.generateThumbnail` (Task 2), `@Environment(\.modelContext)`
- Produces: 36×36 row icon reads thumbnail preferentially; legacy items with no thumbnail lazily generate + persist one on first appearance

- [ ] **Step 1: Add `@Environment(\.modelContext)` to `ClipItemRow`**

Add just below the existing `@State` declarations (around line 19):

```swift
    @Environment(\.modelContext) private var modelContext
```

- [ ] **Step 2: Update `typeIcon` image branch to prefer thumbnail**

Locate the image branch in `typeIcon` (currently around line 253):

```swift
        if item.contentTypeRaw == "image", let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
        }
```

Replace with:

```swift
        if item.contentTypeRaw == "image",
           let thumbData = item.imageThumbnail,
           let nsImage = NSImage(data: thumbData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
        } else if item.contentTypeRaw == "image",
                  let full = item.imageData,
                  let nsImage = NSImage(data: full) {
            // Legacy: no thumbnail yet. Backfill runs from .task; meanwhile
            // render the full image (LazyVStack limits how many rows do this).
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
        }
```

- [ ] **Step 3: Extend the existing `.task(id: item.id)` to backfill thumbnails**

Locate the current `.task(id: item.id)` block (around lines 66–79). Replace it with:

```swift
        .task(id: item.id) {
            // Resolve file bookmark URL for file items (existing behavior)
            if item.contentTypeRaw == "file", let blob = item.fileBookmarks {
                let bookmarks = PasteService.decodeFileBookmarks(blob)
                resolvedFileCount = bookmarks.count
                var isStale = false
                resolvedFileURL = bookmarks.first.flatMap {
                    try? URL(resolvingBookmarkData: $0, options: [], bookmarkDataIsStale: &isStale)
                }
            } else {
                resolvedFileURL = nil
                resolvedFileCount = 0
            }

            // Backfill thumbnail for legacy image items on first appearance.
            // Runs at most once per (id, appearance); LazyVStack limits how many
            // rows execute concurrently.
            if item.contentTypeRaw == "image",
               item.imageThumbnail == nil,
               let full = item.imageData {
                let thumb = await Task.detached(priority: .utility) {
                    ClipboardMonitor.generateThumbnail(full)
                }.value
                if let thumb {
                    item.imageThumbnail = thumb
                    try? modelContext.save()
                }
            }
        }
```

- [ ] **Step 4: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run tests to confirm no regression**

Run the test command. Expected: all tests pass.

- [ ] **Step 6: Commit**

```
git add "Mini Capsule/UI/ClipItemRow.swift"
git commit -m "feat(ui): row icon prefers imageThumbnail; lazy backfill for legacy items

Row rendering no longer instantiates NSImage from full imageData for
the 36×36 icon slot when a thumbnail exists. Legacy items backfill
their thumbnail once on first appearance via Task.detached.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

### Task 6: `CapsuleWindowController` purges cache on collapse

**Files:**
- Modify: `Mini Capsule/UI/CapsuleWindowController.swift` (collapse observer around lines 194–248 and stored refs)

**Interfaces:**
- Consumes: `ClipboardListViewModel.purgeCache()` (from Task 4)
- Produces: on collapse, VM's `[ClipItem]` strong-ref cache is cleared so SwiftData can release the managed objects

The controller currently doesn't hold the `ClipboardListViewModel` — the VM is created inside `CapsuleView`. Simplest hookup: post a new notification `.capsuleShouldPurgeCaches` on collapse, and have `CapsuleView` observe it and call `viewModel.purgeCache()`. Alternatively, add a stored `weak var listViewModel: ClipboardListViewModel?` on the controller and wire it up in `CapsuleView.onAppear`. The notification path is loosely coupled and consistent with the codebase's pattern; use it.

- [ ] **Step 1: Add the notification name**

In `Mini Capsule/Settings/NotificationNames.swift`, inside the Capsule Notifications extension after `clipItemsDidChange`, add:

```swift
    /// Posted when the capsule collapses so consumers can drop heavy caches.
    static let capsuleShouldPurgeCaches = Notification.Name("capsuleShouldPurgeCaches")
```

- [ ] **Step 2: Post from the collapse branch in `CapsuleWindowController.observeExpandedState`**

In `observeExpandedState`, inside the `.capsuleDidChangeExpanded` observer body, right after `self.isExpanded = isExpanded` in the collapse branch (currently around line 241 — the `else` branch that runs `DispatchQueue.main.asyncAfter`), add:

```swift
                    NotificationCenter.default.post(name: .capsuleShouldPurgeCaches, object: nil)
```

Place it *before* the `DispatchQueue.main.asyncAfter` block so the purge fires immediately at logical-collapse time (not delayed by the animation).

- [ ] **Step 3: Observe from `CapsuleExpandedView`**

In `Mini Capsule/UI/CapsuleExpandedView.swift`, add another `.onReceive` next to the existing `.onReceive(NotificationCenter.default.publisher(for: .capsuleEscapePressed))` (around line 50):

```swift
            .onReceive(NotificationCenter.default.publisher(for: .capsuleShouldPurgeCaches)) { _ in
                viewModel.purgeCache()
            }
```

- [ ] **Step 4: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run all tests**

Run the test command. Expected: `** TEST SUCCEEDED **`, all suites pass.

- [ ] **Step 6: Commit**

```
git add "Mini Capsule/Settings/NotificationNames.swift" "Mini Capsule/UI/CapsuleWindowController.swift" "Mini Capsule/UI/CapsuleExpandedView.swift"
git commit -m "feat(lifecycle): purge VM item cache on capsule collapse

Adds .capsuleShouldPurgeCaches notification. Controller posts it on
collapse; CapsuleExpandedView calls viewModel.purgeCache() so the
strong-ref array of ClipItems is dropped and SwiftData can release
external-storage blobs from RAM.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Verification (post-implementation)

Once all six tasks land, run one manual pass — no automation exists for RSS budgets:

1. `open "/Users/vbiso/Library/Developer/Xcode/DerivedData/Mini_Capsule-*/Build/Products/Debug/Mini Capsule.app"` (or launch from Xcode)
2. Open Activity Monitor, filter by "Mini Capsule", note baseline RSS with capsule collapsed
3. Copy 30–50 image files (mixed sizes up to ~2 MB) rapidly by selecting them in Finder + Cmd+C in a loop
4. Expand the capsule, scroll to bottom, note RSS
5. Collapse, wait 5s, note RSS — expected drop as VM cache is purged
6. Re-expand, popover a large image, close popover — expected small transient bump then release

Acceptance: peak RSS ≤ 150 MB across the sequence; collapsed steady-state ≤ ~100 MB.
