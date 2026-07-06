# 胶囊长按拖拽 + 悬停展开修复 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用长按 0.5s 区分拖拽窗口和交互操作，添加拖拽准备态视觉反馈，保持悬停 0.3s 展开逻辑不变。

**Architecture:** CapsuleView 中重写 DragGesture 为长按延迟触发模式，新增 `isDragPrimed` 状态传给子视图。CapsuleCollapsedView 和 CapsuleExpandedView 根据 `isDragPrimed` 渲染光晕视觉反馈。

**Tech Stack:** SwiftUI, AppKit (NSPanel 窗口移动)

## Global Constraints

- 部署目标：macOS 26.5, iOS 26.5, visionOS 26.5
- Swift 5.0
- 悬停展开延迟保持 0.3s，收起延迟保持 1s
- 长按拖拽延迟 0.5s
- 不修改 CapsuleWindowController、ClipItemRow、服务层

---

### Task 1: CapsuleView — 长按拖拽手势 + 状态管理

**Files:**
- Modify: `Mini Capsule/UI/CapsuleView.swift`

**Interfaces:**
- Consumes: `CapsuleCollapsedView` (existing), `CapsuleExpandedView` (existing), `PasteService` (existing)
- Produces: `isDragPrimed: Bool` 传给 `CapsuleCollapsedView` 和 `CapsuleExpandedView`

- [ ] **Step 1: 替换 CapsuleView 中的拖拽手势和状态**

将 `CapsuleView.swift` 中的 `@State private var dragStartFrame: NSRect?` 替换为完整的拖拽状态组，并将 `windowDragGesture` 重写为长按延迟触发方式。

```swift
// Mini Capsule/UI/CapsuleView.swift
import SwiftUI
import SwiftData
import AppKit

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

    // Long-press drag state
    @State private var isDragPrimed = false
    @State private var isDragging = false
    @State private var dragStartFrame: NSRect?
    @State private var dragWorkItem: DispatchWorkItem?

    var body: some View {
        Group {
            if isExpanded {
                CapsuleExpandedView(
                    searchText: $searchText,
                    isDragPrimed: isDragPrimed,
                    onItemTap: { item in
                        PasteService.copyToClipboard(item)
                        item.pasteCount += 1
                        item.lastPastedAt = Date()
                        try? modelContext.save()
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
                    isCapturing: isCapturing,
                    isDragPrimed: isDragPrimed
                )
            }
        }
        .simultaneousGesture(windowDragGesture)
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
        .onChange(of: items.first?.id) { _, _ in
            isCapturing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isCapturing = false
            }
        }
    }

    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Start 0.5s delay on first drag event
                if dragWorkItem == nil && !isDragPrimed && !isDragging {
                    let workItem = DispatchWorkItem {
                        isDragPrimed = true
                    }
                    dragWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
                }

                // Only move window after long-press delay has elapsed
                guard isDragPrimed else { return }

                guard let panel = NSApp.windows.first(where: { $0 is NSPanel }) else { return }
                if !isDragging {
                    isDragging = true
                    dragStartFrame = panel.frame
                }
                guard let startFrame = dragStartFrame else { return }
                var newFrame = startFrame
                newFrame.origin.x += value.translation.width
                newFrame.origin.y -= value.translation.height
                panel.setFrame(newFrame, display: true)
            }
            .onEnded { _ in
                dragWorkItem?.cancel()
                dragWorkItem = nil

                if isDragging {
                    if let panel = NSApp.windows.first(where: { $0 is NSPanel }) {
                        UserDefaults.standard.set([
                            "x": panel.frame.origin.x,
                            "y": panel.frame.origin.y,
                            "w": panel.frame.size.width,
                            "h": panel.frame.size.height
                        ], forKey: "CapsuleWindowFrame")
                    }
                }

                isDragPrimed = false
                isDragging = false
                dragStartFrame = nil
            }
    }

    private func postExpandedNotification() {
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

- [ ] **Step 2: Build 验证编译**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -15
```

Expected: **BUILD FAILED** — 报错 `CapsuleCollapsedView` 和 `CapsuleExpandedView` 缺少 `isDragPrimed` 参数。这是预期的，Task 2 和 Task 3 将修复。

- [ ] **Step 3: Commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add "Mini Capsule/UI/CapsuleView.swift"
git commit -m "feat: replace instant drag with long-press (0.5s) drag gesture in CapsuleView

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: CapsuleCollapsedView — 拖拽准备态视觉反馈

**Files:**
- Modify: `Mini Capsule/UI/CapsuleCollapsedView.swift`

**Interfaces:**
- Consumes: `isDragPrimed: Bool` (from CapsuleView Task 1)
- Produces: 拖拽准备态光晕效果

- [ ] **Step 1: 添加 isDragPrimed 参数和视觉反馈**

```swift
// Mini Capsule/UI/CapsuleCollapsedView.swift
import SwiftUI

struct CapsuleCollapsedView: View {
    let latestItem: ClipItem?
    let isCapturing: Bool
    let isDragPrimed: Bool

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
        .background {
            ZStack {
                // Base material
                Rectangle()
                    .fill(.ultraThinMaterial)

                // Drag-primed glow overlay
                if isDragPrimed {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                }
            }
        }
        .clipShape(Capsule())
        .shadow(
            color: isDragPrimed ? .white.opacity(0.3) : .black.opacity(0.15),
            radius: isDragPrimed ? 6 : 8,
            y: isDragPrimed ? 0 : 4
        )
        .animation(.easeInOut(duration: 0.2), value: isDragPrimed)
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

- [ ] **Step 2: Build 验证编译**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -10
```

Expected: **BUILD FAILED** — 报错 `CapsuleExpandedView` 缺少 `isDragPrimed` 参数。Task 3 将修复。

- [ ] **Step 3: Commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add "Mini Capsule/UI/CapsuleCollapsedView.swift"
git commit -m "feat: add drag-primed glow overlay and shadow to CapsuleCollapsedView

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: CapsuleExpandedView — 拖拽准备态视觉反馈

**Files:**
- Modify: `Mini Capsule/UI/CapsuleExpandedView.swift`

**Interfaces:**
- Consumes: `isDragPrimed: Bool` (from CapsuleView Task 1)
- Produces: 拖拽准备态光晕效果

- [ ] **Step 1: 添加 isDragPrimed 参数和视觉反馈**

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
        .background {
            ZStack {
                // Base material
                Rectangle()
                    .fill(.ultraThinMaterial)

                // Drag-primed glow overlay
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
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -10
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: Commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add "Mini Capsule/UI/CapsuleExpandedView.swift"
git commit -m "feat: add drag-primed glow overlay and border to CapsuleExpandedView

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: 端到端验证

- [ ] **Step 1: Clean build**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' clean build 2>&1 | tail -10
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 2: 验证 iOS build 未被破坏**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -10
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: 运行测试**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: 测试通过

- [ ] **Step 4: Final commit**

```bash
cd "/Users/vbiso/xcode_projects/Mini Capsule"
git add -A
git commit -m "chore: verify all platforms build and tests pass after drag-hover fix

Co-Authored-By: Claude <noreply@anthropic.com>"
```
