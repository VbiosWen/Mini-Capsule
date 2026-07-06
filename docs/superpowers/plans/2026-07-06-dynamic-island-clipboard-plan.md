# 灵动胶囊 macOS 剪贴板管理器 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 macOS 上实现灵动胶囊风格浮动剪贴板管理器——捕获复制内容、悬停展开列表、点击粘贴。

**Architecture:** AppKit NSPanel 作为浮动窗口载体，内嵌 SwiftUI 视图。SwiftData 持久化剪贴板历史。ClipboardMonitor 轮询 NSPasteboard，PasteService 通过 CGEvent 模拟 Cmd+V。macOS 专用功能，iOS/visionOS 保留原有模板行为。

**Tech Stack:** SwiftUI, SwiftData, AppKit (NSPanel), CoreGraphics (CGEvent), Combine (Timer)

## Global Constraints

- 部署目标：macOS 26.5, iOS 26.5, visionOS 26.5
- Swift 5.0
- macOS 胶囊功能不破坏现有 iOS/visionOS 行为
- 剪贴板历史上限 200 条，重启后按频率保留 50 条
- 置顶项不占用 50 条配额
- 粘贴后不恢复剪贴板原内容

---

### Task 1: ClipItem SwiftData 模型

**Files:**
- Create: `Mini Capsule/Models/ClipItem.swift`

**Interfaces:**
- Produces: `ClipItem` @Model class — properties: `id`, `timestamp`, `lastPastedAt`, `pasteCount`, `contentTypeRaw`, `textContent`, `imageData`, `fileBookmarks`, `isPinned`, `sourceAppBundleID`

- [ ] **Step 1: Create Models directory**

```bash
mkdir -p "/Users/vbiso/xcode_projects/Mini Capsule/Mini Capsule/Models"
```

- [ ] **Step 2: Write ClipItem model**

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
    var imageData: Data?
    var fileBookmarks: Data?
    var isPinned: Bool
    var sourceAppBundleID: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        lastPastedAt: Date? = nil,
        pasteCount: Int = 0,
        contentTypeRaw: String,
        textContent: String? = nil,
        imageData: Data? = nil,
        fileBookmarks: Data? = nil,
        isPinned: Bool = false,
        sourceAppBundleID: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.lastPastedAt = lastPastedAt
        self.pasteCount = pasteCount
        self.contentTypeRaw = contentTypeRaw
        self.textContent = textContent
        self.imageData = imageData
        self.fileBookmarks = fileBookmarks
        self.isPinned = isPinned
        self.sourceAppBundleID = sourceAppBundleID
    }
}
```

- [ ] **Step 3: Build to verify compilation**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 4: Commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add "Mini Capsule/Models/ClipItem.swift"
git commit -m "feat: add ClipItem SwiftData model for clipboard history

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: FrequencyCleanupService

**Files:**
- Create: `Mini Capsule/Services/FrequencyCleanupService.swift`

**Interfaces:**
- Consumes: `ClipItem` model (Task 1)
- Produces: `FrequencyCleanupService` — static method `performCleanup(context: ModelContext, keepCount: Int = 50)`

- [ ] **Step 1: Create Services directory**

```bash
mkdir -p "/Users/vbiso/xcode_projects/Mini Capsule/Mini Capsule/Services"
```

- [ ] **Step 2: Write FrequencyCleanupService**

```swift
// Mini Capsule/Services/FrequencyCleanupService.swift
import Foundation
import SwiftData

enum FrequencyCleanupService {
    static func performCleanup(context: ModelContext, keepCount: Int = 50) {
        let allItems = FetchDescriptor<ClipItem>(
            sortBy: [
                SortDescriptor(\.isPinned, order: .reverse),
                SortDescriptor(\.pasteCount, order: .reverse)
            ]
        )

        guard let items = try? context.fetch(allItems) else { return }

        var pinnedCount = 0
        var nonPinnedKept = 0

        let toDelete = items.filter { item in
            if item.isPinned {
                pinnedCount += 1
                return false
            }
            nonPinnedKept += 1
            return nonPinnedKept > keepCount
        }

        for item in toDelete {
            context.delete(item)
        }

        try? context.save()
    }
}
```

- [ ] **Step 3: Build to verify compilation**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 4: Commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add "Mini Capsule/Services/FrequencyCleanupService.swift"
git commit -m "feat: add FrequencyCleanupService for post-restart cleanup

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: PasteService

**Files:**
- Create: `Mini Capsule/Services/PasteService.swift`

**Interfaces:**
- Consumes: `ClipItem` model (Task 1)
- Produces: `PasteService` class — `static var isSelfPaste = false`, `static func paste(_ item: ClipItem, context: ModelContext)`

- [ ] **Step 1: Write PasteService**

```swift
// Mini Capsule/Services/PasteService.swift
import AppKit
import SwiftData
import CoreGraphics

@MainActor
final class PasteService {
    static var isSelfPaste = false

    static func paste(_ item: ClipItem, context: ModelContext) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.contentTypeRaw {
        case "text":
            pasteboard.setString(item.textContent ?? "", forType: .string)
        case "image":
            if let data = item.imageData {
                pasteboard.setData(data, forType: .png)
            }
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

        // Mark to prevent self-capture
        isSelfPaste = true
        defer { isSelfPaste = false }

        // Simulate Cmd+V via CGEvent
        let source = CGEventSource(stateID: .combinedSessionState)

        let cmdKey: CGKeyCode = 0x37
        let vKey: CGKeyCode = 0x09

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)

        let cmdFlag = CGEventFlags.maskCommand.rawValue
        cmdDown?.flags = CGEventFlags(rawValue: cmdFlag)
        vDown?.flags = CGEventFlags(rawValue: cmdFlag)
        vUp?.flags = CGEventFlags(rawValue: cmdFlag)
        cmdUp?.flags = CGEventFlags(rawValue: 0)

        // Post events with small delays
        cmdDown?.post(tap: .cghidEventTap)
        usleep(10_000)
        vDown?.post(tap: .cghidEventTap)
        usleep(10_000)
        vUp?.post(tap: .cghidEventTap)
        usleep(10_000)
        cmdUp?.post(tap: .cghidEventTap)

        // Update paste stats
        item.pasteCount += 1
        item.lastPastedAt = Date()
        try? context.save()
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: Commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add "Mini Capsule/Services/PasteService.swift"
git commit -m "feat: add PasteService with CGEvent Cmd+V simulation

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: ClipboardMonitor

**Files:**
- Create: `Mini Capsule/Services/ClipboardMonitor.swift`

**Interfaces:**
- Consumes: `ClipItem` (Task 1), `PasteService.isSelfPaste` (Task 3)
- Produces: `ClipboardMonitor` ObservableObject — `func start(context: ModelContext)`, `func stop()`

- [ ] **Step 1: Write ClipboardMonitor**

```swift
// Mini Capsule/Services/ClipboardMonitor.swift
import AppKit
import SwiftData
import Combine

@MainActor
final class ClipboardMonitor: ObservableObject {
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var context: ModelContext?

    func start(context: ModelContext) {
        self.context = context
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPasteboard()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        context = nil
    }

    private func checkPasteboard() {
        guard let context = context else { return }
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount

        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        // Skip self-triggered pasteboard changes
        guard !PasteService.isSelfPaste else { return }

        guard let pbTypes = pasteboard.types,
              let content = readPasteboard(pasteboard, types: pbTypes) else { return }

        // Deduplicate against most recent item
        if let latest = try? context.fetch(
            FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        ).first {
            switch (latest.contentTypeRaw, content.type) {
            case ("text", "text") where latest.textContent == content.text:
                latest.timestamp = Date()
                try? context.save()
                return
            case ("image", "image") where latest.imageData == content.image:
                latest.timestamp = Date()
                try? context.save()
                return
            default:
                break
            }
        }

        // Enforce 200 item cap
        enforceCap(context: context, maxCount: 200)

        let item = ClipItem(
            timestamp: Date(),
            contentTypeRaw: content.type,
            textContent: content.text,
            imageData: content.image,
            fileBookmarks: content.fileBookmarks,
            sourceAppBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        context.insert(item)
        try? context.save()
    }

    private func readPasteboard(
        _ pb: NSPasteboard,
        types: [NSPasteboard.PasteboardType]
    ) -> (type: String, text: String?, image: Data?, fileBookmarks: Data?)? {
        if types.contains(.fileURL),
           let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first {
            let bookmarks = try? firstURL.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return ("file", nil, nil, bookmarks)
        }
        if types.contains(.png), let data = pb.data(forType: .png) {
            let image = capImageSize(data, maxBytes: 2_000_000)
            return ("image", nil, image, nil)
        }
        if let text = pb.string(forType: .string) {
            return ("text", text, nil, nil)
        }
        return nil
    }

    private func capImageSize(_ data: Data, maxBytes: Int) -> Data {
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

    private func enforceCap(context: ModelContext, maxCount: Int) {
        let allItems = FetchDescriptor<ClipItem>(
            sortBy: [
                SortDescriptor(\.isPinned, order: .reverse),
                SortDescriptor(\.pasteCount, order: .reverse)
            ]
        )
        guard let items = try? context.fetch(allItems),
              items.count >= maxCount else { return }

        let toDelete = items.filter { !$0.isPinned }.suffix(from: maxCount)
        for item in toDelete {
            context.delete(item)
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: Commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add "Mini Capsule/Services/ClipboardMonitor.swift"
git commit -m "feat: add ClipboardMonitor with dedup, cap, and self-paste filter

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: CapsuleCollapsedView + ClipItemRow (叶子 UI 组件)

**Files:**
- Create: `Mini Capsule/UI/CapsuleCollapsedView.swift`
- Create: `Mini Capsule/UI/ClipItemRow.swift`

**Interfaces:**
- Consumes: `ClipItem` model (Task 1)
- Produces: `CapsuleCollapsedView` — takes `latestItem: ClipItem?`, `isCapturing: Bool`; `ClipItemRow` — takes `item: ClipItem`, `onTap: () -> Void`, `onDelete: () -> Void`

- [ ] **Step 1: Create UI directory**

```bash
mkdir -p "/Users/vbiso/xcode_projects/Mini Capsule/Mini Capsule/UI"
```

- [ ] **Step 2: Write CapsuleCollapsedView**

```swift
// Mini Capsule/UI/CapsuleCollapsedView.swift
import SwiftUI

struct CapsuleCollapsedView: View {
    let latestItem: ClipItem?
    let isCapturing: Bool

    var body: some View {
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
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

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
}
```

- [ ] **Step 3: Write ClipItemRow**

```swift
// Mini Capsule/UI/ClipItemRow.swift
import SwiftUI

struct ClipItemRow: View {
    let item: ClipItem
    var onTap: () -> Void
    var onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            typeIcon
                .frame(width: 28, height: 28)
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
    }

    private var typeIcon: some View {
        switch item.contentTypeRaw {
        case "text":
            return Image(systemName: "doc.text")
                .font(.system(size: 13))
        case "image":
            return Image(systemName: "photo")
                .font(.system(size: 13))
        case "file":
            return Image(systemName: "doc")
                .font(.system(size: 13))
        default:
            return Image(systemName: "questionmark")
                .font(.system(size: 13))
        }
    }

    private var previewText: String {
        switch item.contentTypeRaw {
        case "text":
            return item.textContent?.prefix(50).replacingOccurrences(of: "\n", with: " ") ?? ""
        case "image":
            return "图片"
        case "file":
            return "文件"
        default:
            return "未知"
        }
    }
}
```

- [ ] **Step 4: Build to verify compilation**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 5: Commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add "Mini Capsule/UI/CapsuleCollapsedView.swift" "Mini Capsule/UI/ClipItemRow.swift"
git commit -m "feat: add CapsuleCollapsedView and ClipItemRow leaf components

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: CapsuleExpandedView

**Files:**
- Create: `Mini Capsule/UI/CapsuleExpandedView.swift`

**Interfaces:**
- Consumes: `ClipItem` (Task 1), `ClipItemRow` (Task 5), `PasteService` (Task 3)
- Produces: `CapsuleExpandedView` — takes `searchText: Binding<String>`, `onItemTap: (ClipItem) -> Void`, `onItemDelete: (ClipItem) -> Void`

- [ ] **Step 1: Write CapsuleExpandedView**

```swift
// Mini Capsule/UI/CapsuleExpandedView.swift
import SwiftUI
import SwiftData

struct CapsuleExpandedView: View {
    @Binding var searchText: String
    var onItemTap: (ClipItem) -> Void
    var onItemDelete: (ClipItem) -> Void

    @Query(
        sort: [SortDescriptor(\ClipItem.timestamp, order: .reverse)]
    ) private var allItems: [ClipItem]

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("搜索...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                Button(action: {}) {
                    Image(systemName: "gear")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Item list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredItems) { item in
                        ClipItemRow(
                            item: item,
                            onTap: { onItemTap(item) },
                            onDelete: { onItemDelete(item) }
                        )

                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }

            Divider()

            // Status bar
            HStack {
                if pinnedCount > 0 {
                    Text("📌 已置顶 \(pinnedCount) 条")
                        .font(.system(size: 11))
                }
                Spacer()
                Text("共 \(filteredItems.count) 条")
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(.secondary)
        }
        .frame(width: 280, height: 360)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
    }

    private var filteredItems: [ClipItem] {
        if searchText.isEmpty {
            return allItems
        }
        return allItems.filter { item in
            item.textContent?.localizedCaseInsensitiveContains(searchText) ?? false
        }
    }

    private var pinnedCount: Int {
        allItems.filter(\.isPinned).count
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: Commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add "Mini Capsule/UI/CapsuleExpandedView.swift"
git commit -m "feat: add CapsuleExpandedView with search and item list

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: CapsuleView（根视图 + 状态机）

**Files:**
- Create: `Mini Capsule/UI/CapsuleView.swift`

**Interfaces:**
- Consumes: `CapsuleCollapsedView` (Task 5), `CapsuleExpandedView` (Task 6), `ClipItem` (Task 1), `PasteService` (Task 3)
- Produces: `CapsuleView` root view — manages expanded/collapsed state via hover, posts `NSNotification.Name.capsuleDidChangeExpanded`

- [ ] **Step 1: Write CapsuleView**

```swift
// Mini Capsule/UI/CapsuleView.swift
import SwiftUI
import SwiftData

extension NSNotification.Name {
    static let capsuleDidChangeExpanded = NSNotification.Name("capsuleDidChangeExpanded")
}

struct CapsuleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipItem.timestamp, order: .reverse) private var items: [ClipItem]

    @State private var isExpanded = false
    @State private var isCapturing = false
    @State private var searchText = ""
    @State private var hoverWorkItem: DispatchWorkItem?

    var body: some View {
        Group {
            if isExpanded {
                CapsuleExpandedView(
                    searchText: $searchText,
                    onItemTap: { item in
                        PasteService.paste(item, context: modelContext)
                    },
                    onItemDelete: { item in
                        withAnimation {
                            modelContext.delete(item)
                            try? modelContext.save()
                        }
                    }
                )
            } else {
                CapsuleCollapsedView(
                    latestItem: items.first,
                    isCapturing: isCapturing
                )
            }
        }
        .onHover { hovering in
            hoverWorkItem?.cancel()

            if hovering {
                let workItem = DispatchWorkItem {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded = true
                        searchText = ""
                    }
                    postExpandedNotification()
                }
                hoverWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
            } else {
                let workItem = DispatchWorkItem {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isExpanded = false
                    }
                    postExpandedNotification()
                }
                hoverWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
            }
        }
        // Flash animation when new item captured
        .onChange(of: items.first?.id) { _, _ in
            isCapturing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isCapturing = false
            }
        }
    }

    private func postExpandedNotification() {
        // Short delay to let animation start, then notify window to resize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(
                name: .capsuleDidChangeExpanded,
                object: nil,
                userInfo: ["isExpanded": isExpanded]
            )
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: Commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add "Mini Capsule/UI/CapsuleView.swift"
git commit -m "feat: add CapsuleView root with hover expand/collapse state machine

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: CapsuleWindowController（NSPanel 窗口管理）

**Files:**
- Create: `Mini Capsule/UI/CapsuleWindowController.swift`

**Interfaces:**
- Consumes: `CapsuleView` (Task 7), `NSNotification.Name.capsuleDidChangeExpanded` (Task 7)
- Produces: `CapsuleWindowController` NSWindowController subclass — `func showWindow()`, manages NSPanel lifecycle, frame persistence in UserDefaults

- [ ] **Step 1: Write CapsuleWindowController**

```swift
// Mini Capsule/UI/CapsuleWindowController.swift
import AppKit
import SwiftUI
import SwiftData

final class CapsuleWindowController: NSWindowController {
    private let modelContainer: ModelContainer

    private static let frameKey = "CapsuleWindowFrame"
    private static let collapsedSize = NSSize(width: 200, height: 36)
    private static let expandedSize = NSSize(width: 280, height: 360)

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer

        let savedFrame = Self.loadFrame()

        let panel = NSPanel(
            contentRect: savedFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: panel)

        let capsuleView = CapsuleView()
            .modelContainer(modelContainer)

        panel.contentView = NSHostingView(rootView: capsuleView)
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 18
        panel.contentView?.layer?.masksToBounds = true

        observeExpandedState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindow() {
        window?.makeKeyAndOrderFront(nil)
    }

    private func observeExpandedState() {
        NotificationCenter.default.addObserver(
            forName: .capsuleDidChangeExpanded,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let window = self.window,
                  let isExpanded = notification.userInfo?["isExpanded"] as? Bool else { return }

            let targetSize = isExpanded ? Self.expandedSize : Self.collapsedSize
            let currentFrame = window.frame

            let newFrame = NSRect(
                x: currentFrame.midX - targetSize.width / 2,
                y: currentFrame.maxY - targetSize.height,
                width: targetSize.width,
                height: targetSize.height
            )

            window.setFrame(newFrame, display: true, animate: true)
        }
    }

    override func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    private func saveFrame() {
        guard let frame = window?.frame else { return }
        let frameDict: [String: CGFloat] = [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "w": frame.size.width,
            "h": frame.size.height
        ]
        UserDefaults.standard.set(frameDict, forKey: Self.frameKey)
    }

    private static func loadFrame() -> NSRect {
        guard let dict = UserDefaults.standard.dictionary(forKey: frameKey) as? [String: CGFloat],
              let x = dict["x"],
              let y = dict["y"] else {
            // Default: top-center of main screen
            guard let screen = NSScreen.main else {
                return NSRect(x: 0, y: 0, width: collapsedSize.width, height: collapsedSize.height)
            }
            let screenWidth = screen.visibleFrame.width
            let screenHeight = screen.visibleFrame.maxY
            return NSRect(
                x: (screenWidth - collapsedSize.width) / 2,
                y: screenHeight - collapsedSize.height - 40,
                width: collapsedSize.width,
                height: collapsedSize.height
            )
        }
        return NSRect(x: x, y: y, width: dict["w"] ?? collapsedSize.width, height: dict["h"] ?? collapsedSize.height)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: Commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add "Mini Capsule/UI/CapsuleWindowController.swift"
git commit -m "feat: add CapsuleWindowController with NSPanel and frame persistence

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: 应用入口集成

**Files:**
- Modify: `Mini Capsule/Mini_CapsuleApp.swift`

**Interfaces:**
- Consumes: All previous tasks
- Produces: Fully wired app — model schema updated, capsule window on macOS, ClipboardMonitor started, cleanup runs on launch

- [ ] **Step 1: Read current Mini_CapsuleApp.swift**

```bash
cat "/Users/vbiso/xcode_projects/Mini Capsule/Mini Capsule/Mini_CapsuleApp.swift"
```

- [ ] **Step 2: Rewrite Mini_CapsuleApp.swift with NSApplicationDelegateAdaptor**

```swift
// Mini Capsule/Mini_CapsuleApp.swift
import SwiftUI
import SwiftData

#if os(macOS)
class CapsuleAppDelegate: NSObject, NSApplicationDelegate {
    /// Shared model container, initialized once at startup.
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            ClipItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    private var capsuleWindowController: CapsuleWindowController?
    private var clipboardMonitor: ClipboardMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Frequency cleanup on startup
        FrequencyCleanupService.performCleanup(
            context: Self.sharedModelContainer.mainContext,
            keepCount: 50
        )

        // Create capsule window
        let controller = CapsuleWindowController(modelContainer: Self.sharedModelContainer)
        controller.showWindow()
        capsuleWindowController = controller

        // Start clipboard monitoring
        let monitor = ClipboardMonitor()
        monitor.start(context: Self.sharedModelContainer.mainContext)
        clipboardMonitor = monitor
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stop()
    }
}
#endif

@main
struct Mini_CapsuleApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor var appDelegate: CapsuleAppDelegate
    #else
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            ClipItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    #endif

    var body: some Scene {
        #if os(macOS)
        // macOS: hide main window, capsule window managed by CapsuleAppDelegate
        WindowGroup {
            EmptyView()
                .hidden()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        #else
        // iOS / visionOS: keep existing behavior
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        #endif
    }
}
```

- [ ] **Step 3: Build to verify compilation**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -10
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 4: Commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add "Mini Capsule/Mini_CapsuleApp.swift"
git commit -m "feat: integrate capsule window, clipboard monitor, and cleanup into app entry

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 10: 端到端验证

- [ ] **Step 1: Full clean build**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' clean build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 2: Run unit tests**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: Tests pass (existing Swift Testing tests still work)

- [ ] **Step 3: Verify iOS build not broken**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 4: Final commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add -A
git commit -m "chore: verify all platforms build and tests pass

Co-Authored-By: Claude <noreply@anthropic.com>"
```
