# File Capture & UI Refinements — 文件监听、首字符图标、单次点击复制

**Date:** 2026-07-08
**Status:** draft

## Problem

三个独立但相邻的可用性问题：

1. **文件复制未展示**：`ClipboardMonitor` 已经读到 `.fileURL`，但 UI 只显示"文件"两字，没有文件名、没有真实系统图标，也不支持一次复制多个文件。
2. **文本项图标信息量低**：文本项统一使用 `doc.text` 图标，无法在快速扫视胶囊时区分内容。
3. **胶囊内点击需两次才复制**：展开动画完成后还有 350ms 屏蔽期（`isExpandingReady`），第一次点击会被 `guard isInteractive` 吞掉，用户需要点第二次。

## Design

### 1. 单次点击复制

移除 `ClipItemRow.onTapGesture` 中的 `guard isInteractive else { return }`。展开后就允许点击；仍保留在多选模式下点击切换选中的行为。`isExpandingReady` 状态本身继续保留，用于 hover 悬停 UI（如删除按钮出现时机），不影响点击。

**改动**：`ClipItemRow.swift` — 删一行 guard。

### 2. 文本项首字符 + 稳定随机色

**颜色**：基于 `item.id.uuidString` 的 FNV-1a 哈希映射到 SwiftUI `Color(hue:saturation:brightness:)`（HSB）：
- `hue`: 0.0–1.0（哈希低 16 位 / 65535）
- `saturation`: 0.55–0.75（次 16 位取模到 0.20 区间 + 0.55）
- `brightness`: 0.55–0.70（再取 16 位取模到 0.15 区间 + 0.55）

理由：同一 item 每次都得到同一颜色（不闪烁）；HSB 空间限定 S/B 范围可保证在浅色 `.ultraThinMaterial` 和深色系统背景下都能读到明显的色相区分且饱和度够。避开纯黑/纯白/低饱和的浑浊区。

**字符**：`item.textContent` 首个非空白 Character（`Unicode.Scalar` 层截取，支持 emoji、中/英）。为空时回退到 `doc.text` 图标。

**样式**：
- 字体：`.system(size: 18, weight: .semibold, design: .rounded)`
- 前景色：上面的动态色
- 背景：保持现有 `.quaternary` 圆角容器（36×36）

**位置**：新增 helper `Color.deterministic(from:)` 到 `Mini Capsule/Utilities/ColorHex.swift`，接收 `String` 返回 `Color`。

### 3. 文件复制监听 & 展示

#### 数据模型（不改 `ClipItem` 字段）

- `imageFileName` **复用**为文件名（多文件时存首个）。字段是 `String?`，语义扩展到 file 类型。
- `fileBookmarks` **改为可容纳多个 bookmark**：
  - 存储格式：`JSONEncoder` 编码的 `[Data]`（每个元素是一个 URL 的 bookmarkData）
  - **向后兼容**：读取时先尝试 `JSONDecoder.decode([Data].self)`；失败则把整个 `Data` 当作单个 bookmark 走旧路径。写入始终用新格式。

#### `ClipboardMonitor.readPasteboard`

file 分支修改为：

```swift
if types.contains(.fileURL),
   let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
   !urls.isEmpty {
    let bookmarks: [Data] = urls.compactMap {
        try? $0.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    guard !bookmarks.isEmpty else { return nil }
    let encoded = try? JSONEncoder().encode(bookmarks)
    let firstName = urls.first?.lastPathComponent
    return ("file", nil, nil, encoded, firstName)
}
```

`checkPasteboard` 的 file 分支插入时同时写入 `imageFileName: content.fileName`。

#### `PasteService`

新增 helper：

```swift
static func decodeFileBookmarks(_ data: Data) -> [Data] {
    if let arr = try? JSONDecoder().decode([Data].self, from: data), !arr.isEmpty {
        return arr
    }
    return [data]  // legacy: single bookmark
}
```

`copyToClipboard` 和 `paste` 的 file 分支：

```swift
case "file":
    if let bookmarkData = item.fileBookmarks {
        let bookmarks = decodeFileBookmarks(bookmarkData)
        var isStale = false
        let urls: [URL] = bookmarks.compactMap {
            try? URL(resolvingBookmarkData: $0, options: [], bookmarkDataIsStale: &isStale)
        }
        if !urls.isEmpty {
            pasteboard.writeObjects(urls as [NSURL])
        }
    }
```

#### UI

`ClipboardListViewModel`：
- `ContentFilter` 增加 `case file = "文件"`，`systemImage` 为 `"doc"`。
- `filteredItems` 的 `filterType` switch 增加 `.file: allItems.filter { $0.contentTypeRaw == "file" }`。

`ClipItemRow`：
- `typeIcon`：file 类型时用 `NSWorkspace.shared.icon(forFile:)` 生成 `NSImage` 展示。为拿到文件路径，需要先解出第一个 bookmark。为避免每次渲染都解析（性能 + 权限提示），把结果缓存到 `@State private var resolvedFileURL: URL?`，在 `.task` / `.onAppear` 里解析一次。若解析失败，回退到 `doc` symbol。
- `previewText`：file 分支返回 `imageFileName ?? "文件"`；多文件时（bookmark 数 > 1）附加 " 等 N 项"。
- `iconForType`：text 分支不再返回 `doc.text`，改为返回首字符视图（由 helper `firstCharView` 生成）。

`CapsuleCollapsedView.summaryText`：
- file 分支：`📁 \(item.imageFileName ?? "文件")`。

### 改动文件

| 文件 | 改动 |
|---|---|
| `Mini Capsule/UI/ClipItemRow.swift` | 移除点击 guard、text 首字符图标、file 系统图标 & 文件名预览 |
| `Mini Capsule/UI/CapsuleCollapsedView.swift` | file 分支显示文件名 |
| `Mini Capsule/UI/ClipboardListViewModel.swift` | `ContentFilter` 加 `.file` |
| `Mini Capsule/Services/ClipboardMonitor.swift` | 多文件 bookmarks + fileName |
| `Mini Capsule/Services/PasteService.swift` | `decodeFileBookmarks` + 多文件写入 |
| `Mini Capsule/Utilities/ColorHex.swift` | 新增 `Color.deterministic(from:)` |
| `Mini CapsuleTests/ClipboardMonitorTests.swift` | 新增多文件 bookmark 编码测试 |
| `Mini CapsuleTests/PasteServiceTests.swift` | 新增 `decodeFileBookmarks` 单元测试（含 legacy 兼容） |
| `Mini CapsuleTests/ColorHexTests.swift` | `deterministic(from:)` 稳定性测试 |

### 边界情况

| 场景 | 行为 |
|---|---|
| 复制多个文件 | 全部 bookmarks 编入 `[Data]`；粘贴时 `writeObjects` 全部 URL |
| 单文件（新代码） | `[Data]` 只有一项，粘贴与旧行为一致 |
| 已存在的旧单 bookmark 数据（升级用户） | `decodeFileBookmarks` fallback 到 legacy `[data]`，不丢失 |
| 文件在系统中被删除 | bookmark 解析失败，icon 回退 `doc`；粘贴 URL 数组为空，pasteboard 不写入 |
| 空文本 item（罕见） | 首字符 helper 回退到 `doc.text` symbol |
| Emoji 首字符 | 用 `Character` 而非 `.first` 到 `Unicode.Scalar`，避免拆分 grapheme cluster |
| 展开动画期间点击 | 允许（`guard isInteractive` 移除后）；操作对已展开列表安全 |

### 非目标

- 不改 `ClipItem` 的 `@Model` schema — 复用已有字段。
- 不做文件预览 popover 图片（file 类型只显示文件名 + icon）。
- 不做 icon 缓存到 SwiftData（每次由 `NSWorkspace` 动态生成，够快）。

### 假设

- 当前 target 未开启 App Sandbox（否则 bookmark 解析需要 security-scoped 访问；查 `Personal.entitlements` 和 `Development.entitlements` 确认，本次不引入 sandbox 相关代码）。

## Implementation Plan

1. `Color.deterministic(from:)` + tests。
2. `ClipItemRow` text 首字符图标（读旧 tests 通过）。
3. `ClipItemRow` 移除 `guard isInteractive`（单次点击）。
4. `ContentFilter.file` + view model 筛选。
5. `ClipboardMonitor` file 分支多 URL + fileName。
6. `PasteService.decodeFileBookmarks` + 多文件粘贴（含 legacy 兼容测试）。
7. `ClipItemRow` file 分支：解析首 URL、`NSWorkspace` 系统图标、文件名 preview。
8. `CapsuleCollapsedView` file 分支 summary 文本更新。
9. `xcodebuild build` + `xcodebuild test` 全绿。
