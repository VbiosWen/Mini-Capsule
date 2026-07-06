# 图片条目预览 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 点击图片类型的列表条目时，在条目右侧弹出预览浮层（最大 200×300），小图保持原始尺寸不放大，点击其他区域关闭。

**Architecture:** ClipItemRow 增加 `showImagePreview` 状态和预览 overlay，通过 `onPreviewStateChanged` 回调通知父视图 CapsuleExpandedView。父视图管理预览互斥：点击新条目时关闭旧预览。

**Tech Stack:** SwiftUI, AppKit (NSImage)

## Global Constraints

- 部署目标：macOS 26.5, iOS 26.5, visionOS 26.5
- Swift 5.0
- 预览最大尺寸：200×300，小图不放大
- 只有 `contentTypeRaw == "image"` 的条目才弹预览
- 图片条目点击弹预览（不粘贴），文本/文件条目点击仍粘贴
- 不修改 CapsuleView、CapsuleCollapsedView、CapsuleWindowController、服务层

---

### Task 1: ClipItemRow — 图片预览 overlay + 点击切换

**Files:**
- Modify: `Mini Capsule/UI/ClipItemRow.swift`

**Interfaces:**
- Consumes: `ClipItem` model (existing), `item.imageData: Data?`
- Produces: `showImagePreview: Bool` state, `onPreviewStateChanged: ((Bool) -> Void)?` callback

- [ ] **Step 1: 重写 ClipItemRow 添加图片预览功能**

```swift
// Mini Capsule/UI/ClipItemRow.swift
import SwiftUI

struct ClipItemRow: View {
    let item: ClipItem
    var onTap: () -> Void
    var onDelete: () -> Void
    var onPreviewStateChanged: ((Bool) -> Void)?

    @State private var isHovering = false
    @State private var showImagePreview = false

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
            if item.contentTypeRaw == "image" {
                showImagePreview.toggle()
                onPreviewStateChanged?(showImagePreview)
            } else {
                onTap()
            }
        }
        .overlay {
            if showImagePreview, let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
                HStack {
                    Spacer()
                    imagePreview(nsImage)
                        .offset(x: 280 + 8, y: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func imagePreview(_ nsImage: NSImage) -> some View {
        let imageSize = nsImage.size
        let maxWidth: CGFloat = 200
        let maxHeight: CGFloat = 300

        // Calculate display size: min(original, max), preserving aspect ratio
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

- [ ] **Step 2: Build 验证编译**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -10
```

Expected: **BUILD SUCCEEDED**（CapsuleExpandedView 适配在 Task 2 完成）

- [ ] **Step 3: Commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add "Mini Capsule/UI/ClipItemRow.swift"
git commit -m "feat: add image preview overlay to ClipItemRow on click

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: CapsuleExpandedView — 预览互斥管理

**Files:**
- Modify: `Mini Capsule/UI/CapsuleExpandedView.swift`

**Interfaces:**
- Consumes: `ClipItemRow` with `onPreviewStateChanged` (Task 1)
- Produces: 管理当前展示预览的条目 ID，点击其他条目或搜索时关闭预览

- [ ] **Step 1: 添加 onPreviewStateChanged 回调到 ClipItemRow 调用**

```swift
// Mini Capsule/UI/CapsuleExpandedView.swift
// 在 CapsuleExpandedView 中添加:
// @State private var previewingItemID: UUID?
//
// 在 ForEach 中的 ClipItemRow 调用添加 onPreviewStateChanged:

ClipItemRow(
    item: item,
    onTap: {
        // Close any open preview when tapping another item
        previewingItemID = nil
        onItemTap(item)
    },
    onDelete: {
        previewingItemID = nil
        onItemDelete(item)
    },
    onPreviewStateChanged: { isShowing in
        previewingItemID = isShowing ? item.id : nil
    }
)
```

完整文件：

```swift
// Mini Capsule/UI/CapsuleExpandedView.swift
import SwiftUI
import SwiftData

struct CapsuleExpandedView: View {
    @Binding var searchText: String
    let isDragPrimed: Bool
    var onItemTap: (ClipItem) -> Void
    var onItemDelete: (ClipItem) -> Void

    @Query(
        sort: [SortDescriptor(\ClipItem.timestamp, order: .reverse)]
    ) private var allItems: [ClipItem]

    @State private var previewingItemID: UUID?

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
                    .onChange(of: searchText) { _, _ in
                        previewingItemID = nil
                    }

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
                            onTap: {
                                previewingItemID = nil
                                onItemTap(item)
                            },
                            onDelete: {
                                previewingItemID = nil
                                onItemDelete(item)
                            },
                            onPreviewStateChanged: { isShowing in
                                previewingItemID = isShowing ? item.id : nil
                            }
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
        .background {
            ZStack {
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

- [ ] **Step 2: Build 验证编译**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -10
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: Commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add "Mini Capsule/UI/CapsuleExpandedView.swift"
git commit -m "feat: add preview dismiss logic in CapsuleExpandedView

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: 端到端验证

- [ ] **Step 1: Clean build**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' clean build 2>&1 | tail -10
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 2: 验证 iOS build 未被破坏**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -10
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: Commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add -A
git commit -m "chore: verify all platforms build after image preview feature

Co-Authored-By: Claude <noreply@anthropic.com>"
```
