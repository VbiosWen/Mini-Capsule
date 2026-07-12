# Memory Budget — 150 MB Cap

**Date:** 2026-07-11
**Status:** approved

## Context

Mini Capsule 目前无内存红线控制。核心风险点集中在图片：`ClipItem.imageData`
是内联 SwiftData 属性（未标 `@Attribute(.externalStorage)`），单条图片默认
上限 2 MB，历史条数默认 200 —— 全部拉进内存时最坏 ~400 MB 常驻。列表行
（`ClipItemRow.typeIcon`）每次为 36×36 显示都要从原始 `imageData` 实例化
整张 `NSImage`；`ClipboardListViewModel.filteredItems` 是纯 computed，每次
SwiftUI 重绘都会 fetch 全部 `ClipItem`。用户希望"提前定 150 MB 红线"，本
设计目标是在不动用户可配置项（`imageMaxSizeMB` / `historyMaxCount`）、不
砍功能的前提下，让 RSS 在真实工作负载（100+ 张 2 MB 图）下也稳在 150 MB
内。Swift 用 ARC 不是 GC，"最快回收"落实到 autoreleasepool + 尽早解除
强引用。

## Design

### 分层

| 层 | 位置 | 变更 |
|---|---|---|
| Model | `ClipItem` | `imageData` 加外部存储；新增 `imageThumbnail` 外部存储列 |
| 捕获 | `ClipboardMonitor` | 新 `generateThumbnail`；三处图片处理包 `autoreleasepool`；save 后 post 通知 |
| 渲染 | `ClipItemRow` | 行图标优先缩略图；popover 依旧全图但 `.onDisappear` 释放 |
| VM | `ClipboardListViewModel` | `filteredItems` 变成 keyed 缓存 + 失效机制 |
| 生命周期 | `CapsuleWindowController` | 面板折叠时 `purgeCache()` |
| 迁移 | `ClipItemRow` | 旧行懒回填缩略图 |

### 1. Model — 外部存储 + 缩略图列

`Mini Capsule/Models/ClipItem.swift`

```swift
@Attribute(.externalStorage) var imageData: Data?
@Attribute(.externalStorage) var imageThumbnail: Data?
```

- `init` 追加 `imageThumbnail: Data? = nil` 参数
- SwiftData 加列 + 加外部存储属性都是 lightweight 迁移，旧数据保持内联但读
  取路径不变；新写入会走外部文件

### 2. 捕获路径 — 缩略图 + autoreleasepool

`Mini Capsule/Services/ClipboardMonitor.swift`

**新 helper**
```swift
static func generateThumbnail(_ data: Data, maxDimension: CGFloat = 72) -> Data? {
    autoreleasepool {
        guard let image = NSImage(data: data) else { return nil }
        let src = image.size
        let scale = min(1.0, maxDimension / max(src.width, src.height))
        let target = NSSize(width: src.width * scale, height: src.height * scale)
        let out = NSImage(size: target)
        out.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target),
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

**改动点**
- `capImageSize` 整体包 `autoreleasepool { ... }`
- `nsImageToPNGData` 同样
- `checkPasteboard` 每个 `context.insert(ClipItem(...))` 的图片分支：在 insert
  前调用 `Self.generateThumbnail(imageData)`，作为 `imageThumbnail` 参数
- `try? context.save()` 后 post `.clipItemsDidChange`（新通知）

### 3. Notification

`Mini Capsule/Settings/NotificationNames.swift` 新增：
```swift
static let clipItemsDidChange = Notification.Name("clipItemsDidChange")
```

### 4. 渲染路径 — 行用缩略图

`Mini Capsule/UI/ClipItemRow.swift`

```swift
@Environment(\.modelContext) private var modelContext

// typeIcon 图片分支：
if item.contentTypeRaw == "image" {
    if let thumb = item.imageThumbnail, let ns = NSImage(data: thumb) {
        Image(nsImage: ns).resizable().aspectRatio(contentMode: .fill).frame(width: 36, height: 36)
    } else if let full = item.imageData, let ns = NSImage(data: full) {
        Image(nsImage: ns).resizable().aspectRatio(contentMode: .fill).frame(width: 36, height: 36)
    } else {
        iconForType.font(.system(size: 15))
    }
}
```

Popover 图片预览维持 `imageData` 直用；给 `popoverContent` 的 image 分支的
外层 `.popover` 加 `.onDisappear { /* nothing needed — SwiftUI drops NSImage */ }`
（NSImage 是本地变量，popover 关闭即释放，无需显式清理，但保留 onDisappear 用于
未来插入清理钩子）。

### 5. VM — filteredItems 缓存

`Mini Capsule/UI/ClipboardListViewModel.swift`

```swift
private struct CacheKey: Equatable {
    let search: String
    let filter: ContentFilter
    let version: Int
}
@ObservationIgnored private var itemsCache: [ClipItem] = []
@ObservationIgnored private var cacheKey: CacheKey?
private var cacheVersion: Int = 0  // tracked：变化触发 SwiftUI 重绘再读一次

func invalidateCache() {
    cacheVersion &+= 1
    cacheKey = nil
    itemsCache = []
}

func purgeCache() {
    cacheKey = nil
    itemsCache = []
}

var filteredItems: [ClipItem] {
    let key = CacheKey(search: searchText, filter: filterType, version: cacheVersion)
    if key == cacheKey { return itemsCache }
    // 现有 fetch + filter + sort 逻辑不变，结果存入 itemsCache
    ...
    cacheKey = key
    itemsCache = result
    return result
}
```

**失效点**（每处内部 write op 结束后调用 `invalidateCache()`）
- `copyItem` / `pasteItem` / `deleteItem` / `deleteSelected` / `togglePin` / `editText`

**外部失效**（VM `init` 里订阅一次，用 `NotificationCenter.default.addObserver`）
- `.clipItemsDidChange` → `invalidateCache()`

### 6. 生命周期 — 折叠时释放引用

`Mini Capsule/UI/CapsuleWindowController.swift`

在监听 `.capsuleDidChangeExpanded` 的地方，当 expanded 变为 false 时调用
`viewModel.purgeCache()`。持有的 `[ClipItem]` 引用清空后 SwiftData context
会释放对应的对象上下文，外部 blob 引用也随之释放。

### 7. 旧行懒回填缩略图

`ClipItemRow.swift` 现有的 `.task(id: item.id)` 追加：

```swift
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
```

LazyVStack 只渲染可见行，`task(id:)` 每个 id 至多一次，滚动即回填。生成失败
就继续走全图回退，无 UI 抖动（36×36 尺寸下缩略图与全图外观一致）。

## 数据流

**面板折叠稳态**
- VM `itemsCache = []`，无 ClipItem 强引用
- SwiftData context 只保有 metadata，外部 blob 未加载
- 期望 RSS：SwiftUI/AppKit baseline (~60–80 MB) + SwiftData (~10 MB) ≈ ~80 MB

**面板展开滚动**
- VM cache 命中或 fetch 一次，持有 ~100–200 ClipItem 元数据
- 可见行读 `imageThumbnail`（~5 KB × 屏内 ~8 行 ≈ 40 KB）
- `imageData` 不加载

**Popover 打开**
- 单一 ClipItem 触发 `imageData` fault-in，NSImage 常驻直到 popover 关
- 关闭后 SwiftUI 释放 View 与 NSImage 引用

## Testing

**Unit**
- `ClipboardMonitorTests.generateThumbnailProducesValidPNGUnderMaxDim` — 200×300
  输入，输出 PNG 长边 ≤ 72
- `ClipboardMonitorTests.generateThumbnailReturnsNilOnGarbageData`
- `ClipboardListViewModelTests.filteredItemsCachesResultUntilKeyChanges` — 用
  MockContext 计 fetch 次数
- `ClipboardListViewModelTests.invalidateCacheOnNotification` — post
  `.clipItemsDidChange` 后下一次访问触发 fetch

**手工**
- Instruments Allocations：冷启动 → 打开胶囊 → 通过测试工具连续复制 50 张 2 MB
  图 → 折叠 → 再打开滚到底 → 断言 peak resident ≤ 150 MB，稳态 ≤ 100 MB

## 迁移 & 兼容

- `imageData` 加 `@Attribute(.externalStorage)`：SwiftData 认为是属性元数据
  变更，automatic lightweight，无需自定义 migration；已内联的旧 blob 保持
  内联，新写入走外部
- `imageThumbnail` 新列：additive，旧行为 nil，走 Section 7 懒回填
- `.clipItemsDidChange` 新通知：VM 是唯一订阅方；ClipboardMonitor 添加 post
  是纯增量

## Non-goals

- 不改用户可配置的 `imageMaxSizeMB` / `historyMaxCount` 默认值
- 不删除背景图功能（`SettingsData.backgroundImageData` 保持内联，容量由用户上传决定）
- 不引入总字节硬预算或调试 HUD（真的观察到超红线再加）

## Implementation Order

1. Model：`ClipItem` 加两个属性 + init 参数
2. 通知：`NotificationNames.swift` 加 `.clipItemsDidChange`
3. 捕获：`ClipboardMonitor` 加 `generateThumbnail` + autoreleasepool + insert 时填 thumbnail + post 通知
4. VM：`ClipboardListViewModel` 换 filteredItems 为 cached；写操作触发失效；订阅通知
5. 生命周期：`CapsuleWindowController` 折叠时 `purgeCache()`
6. 渲染：`ClipItemRow` 行图标优先缩略图 + 懒回填 task
7. 单测：新 helper 与 cache 行为
8. Instruments 手工验证
