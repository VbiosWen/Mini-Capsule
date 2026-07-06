# 图片条目优化 + MD5 去重 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 图片条目显示文件名和缩略图，悬停弹出预览，MD5 去重避免复制同一图片产生多条记录。

**Architecture:** ClipItem 模型新增 `imageFileName` 和 `imageMD5`。ClipboardMonitor 捕获图片时提取文件名、计算 MD5、按 MD5 去重。ClipItemRow 图片条目用 36×36 缩略图替换图标，显示图片名称。

**Tech Stack:** SwiftUI, SwiftData, CryptoKit (MD5), AppKit

## Global Constraints

- 部署目标：macOS 26.5, iOS 26.5, visionOS 26.5
- Swift 5.0
- 缩略图 36×36，等比填充裁剪
- 图片名：有文件名用文件名，否则 `来源APP-短ID`
- MD5 去重：同 MD5 图片不新增，只更新时间（置顶）
- 不修改 CapsuleView、CapsuleCollapsedView、CapsuleExpandedView、CapsuleWindowController、PasteService

---

### Task 1: ClipItem 模型 — 新增 imageFileName 和 imageMD5

**Files:**
- Modify: `Mini Capsule/Models/ClipItem.swift`

**Interfaces:**
- Produces: `ClipItem.imageFileName: String?`, `ClipItem.imageMD5: String?`

- [ ] **Step 1: 添加新字段到 ClipItem 模型**

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
    var imageFileName: String?
    var imageMD5: String?
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
        imageFileName: String? = nil,
        imageMD5: String? = nil,
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
        self.imageFileName = imageFileName
        self.imageMD5 = imageMD5
        self.fileBookmarks = fileBookmarks
        self.isPinned = isPinned
        self.sourceAppBundleID = sourceAppBundleID
    }
}
```

- [ ] **Step 2: Build 验证编译**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD FAILED** — ClipboardMonitor 等调用 `ClipItem(...)` 的地方缺少新参数。Task 2 将修复。

- [ ] **Step 3: Commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add "Mini Capsule/Models/ClipItem.swift"
git commit -m "feat: add imageFileName and imageMD5 fields to ClipItem model

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: ClipboardMonitor — 文件名提取 + MD5 计算 + MD5 去重

**Files:**
- Modify: `Mini Capsule/Services/ClipboardMonitor.swift`

**Interfaces:**
- Consumes: `ClipItem` with `imageFileName` / `imageMD5` (Task 1)
- Produces: 图片文件名提取、MD5 计算、MD5 去重查询

- [ ] **Step 1: 重写 ClipboardMonitor 添加文件名提取、MD5 计算和去重**

```swift
// Mini Capsule/Services/ClipboardMonitor.swift
import AppKit
import SwiftData
import Combine
import CryptoKit

@MainActor
final class ClipboardMonitor: ObservableObject {
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var context: ModelContext?

    func start(context: ModelContext) {
        self.context = context
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { [weak self] in
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

        // MD5-based dedup for images
        if content.type == "image", let imageData = content.image {
            let md5 = Self.md5Hash(imageData)
            let imagePredicate = #Predicate<ClipItem> { $0.contentTypeRaw == "image" && $0.imageMD5 == md5 }
            let existing = try? context.fetch(FetchDescriptor<ClipItem>(predicate: imagePredicate))
            if let existingItem = existing?.first {
                existingItem.timestamp = Date()
                try? context.save()
                return
            }

            // Enforce 200 item cap
            enforceCap(context: context, maxCount: 200)

            let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let appName = NSWorkspace.shared.frontmostApplication?.localizedName
            let fileName = content.fileName ?? "\(appName ?? "未知")-\(UUID().uuidString.prefix(4))"

            let item = ClipItem(
                timestamp: Date(),
                contentTypeRaw: content.type,
                imageData: imageData,
                imageFileName: fileName,
                imageMD5: md5,
                sourceAppBundleID: sourceApp
            )
            context.insert(item)
            try? context.save()
            return
        }

        // Text/image dedup by content (existing logic)
        if let latest = try? context.fetch(
            FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        ).first {
            switch (latest.contentTypeRaw, content.type) {
            case ("text", "text") where latest.textContent == content.text:
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
            fileBookmarks: content.fileBookmarks,
            sourceAppBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        context.insert(item)
        try? context.save()
    }

    private func readPasteboard(
        _ pb: NSPasteboard,
        types: [NSPasteboard.PasteboardType]
    ) -> (type: String, text: String?, image: Data?, fileBookmarks: Data?, fileName: String?)? {
        // Check image first — some apps put both fileURL and PNG on pasteboard
        if types.contains(.png), let data = pb.data(forType: .png) {
            let image = capImageSize(data, maxBytes: 2_000_000)
            let fileName = extractFileName(from: pb, types: types)
            return ("image", nil, image, nil, fileName)
        }
        if types.contains(.tiff), let data = pb.data(forType: .tiff) {
            let image = capImageSize(data, maxBytes: 2_000_000)
            let fileName = extractFileName(from: pb, types: types)
            return ("image", nil, image, nil, fileName)
        }
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
        if let text = pb.string(forType: .string) {
            return ("text", text, nil, nil, nil)
        }
        return nil
    }

    // MARK: - Helpers

    private func extractFileName(from pb: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> String? {
        // Try to extract filename if fileURL is also present alongside the image
        if types.contains(.fileURL),
           let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first {
            return firstURL.lastPathComponent
        }
        return nil
    }

    static func md5Hash(_ data: Data) -> String {
        CryptoKit.Insecure.MD5.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
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
        let allItems = FetchDescriptor<ClipItem>(sortBy: [])
        guard let items = try? context.fetch(allItems),
              items.count >= maxCount else { return }

        let sorted = items.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.pasteCount > b.pasteCount
        }
        let toDelete = sorted.filter { !$0.isPinned }.suffix(from: maxCount)
        for item in toDelete {
            context.delete(item)
        }
    }
}
```

- [ ] **Step 2: Build 验证编译**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: Commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add "Mini Capsule/Services/ClipboardMonitor.swift"
git commit -m "feat: add MD5 dedup, filename extraction, and image name for clipboard images

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: ClipItemRow — 36×36 缩略图 + 图片名称

**Files:**
- Modify: `Mini Capsule/UI/ClipItemRow.swift`

**Interfaces:**
- Consumes: `ClipItem.imageFileName` (Task 1), `ClipItem.imageData` (existing)

- [ ] **Step 1: 重写 ClipItemRow — 图片条目用缩略图 + 图片名**

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
        .popover(isPresented: Binding(
            get: { isHovering && item.contentTypeRaw == "image" },
            set: { isHovering = $0 }
        ), arrowEdge: .trailing) {
            if let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
                imagePreview(nsImage)
                    .padding(8)
            }
        }
    }

    // MARK: - Image Preview

    @ViewBuilder
    private func imagePreview(_ nsImage: NSImage) -> some View {
        let imageSize = nsImage.size
        let maxWidth: CGFloat = 200
        let maxHeight: CGFloat = 300

        let scaleX = imageSize.width > maxWidth ? maxWidth / imageSize.width : 1.0
        let scaleY = imageSize.height > maxHeight ? maxHeight / imageSize.height : 1.0
        let scale = min(scaleX, scaleY)
        let displayWidth = imageSize.width * scale
        let displayHeight = imageSize.height * scale

        Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: displayWidth, height: displayHeight)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    // MARK: - Type Icon / Thumbnail

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
        case "text":
            return Image(systemName: "doc.text")
        case "file":
            return Image(systemName: "doc")
        default:
            return Image(systemName: "questionmark")
        }
    }

    // MARK: - Preview Text

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
}
```

- [ ] **Step 2: Build 验证编译**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: Commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add "Mini Capsule/UI/ClipItemRow.swift"
git commit -m "feat: use 36x36 thumbnail and image name for image items

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: 端到端验证

- [ ] **Step 1: Clean build**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' clean build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 2: 验证 iOS build**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: Commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add -A
git commit -m "chore: verify all platforms build after image thumbnail and MD5 dedup

Co-Authored-By: Claude <noreply@anthropic.com>"
```
