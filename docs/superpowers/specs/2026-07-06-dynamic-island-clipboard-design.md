# 灵动胶囊 — macOS 剪贴板管理器设计文档

**日期**: 2026-07-06
**状态**: 已确认

---

## 概述

在 macOS 上实现一个"灵动胶囊"风格的剪贴板管理器。以桌面浮动悬浮窗形态存在，自动捕获用户复制/剪切的内容（文本、图片、文件），点击任意条目直接粘贴到当前活跃应用。鼠标悬停时从紧凑胶囊条展开为列表面板，移开后自动收缩。

---

## 架构

```
┌─────────────────────────────────────────────────────┐
│                    Mini Capsule App                   │
├─────────────────────────────────────────────────────┤
│  SwiftUI App Entry (Mini_CapsuleApp)                  │
│  ├── 启动时创建 CapsuleWindowController               │
│  └── 可选：保留或隐藏主 SwiftUI 窗口                   │
├─────────────────────────────────────────────────────┤
│  AppKit 层                                           │
│  ├── CapsuleWindowController (NSWindowController)     │
│  │   └── 管理 NSPanel：悬浮层级、跨空间、位置记忆      │
│  └── CapsuleWindow (NSPanel)                          │
│      └── hosting SwiftUI CapsuleView                  │
├─────────────────────────────────────────────────────┤
│  SwiftUI 层                                          │
│  ├── CapsuleView（根视图，管理展开/收起状态）           │
│  │   ├── CapsuleCollapsedView（胶囊条）                │
│  │   └── CapsuleExpandedView（列表 + 搜索）            │
│  └── ClipItemRow（单条记录行）                         │
├─────────────────────────────────────────────────────┤
│  服务层                                               │
│  ├── ClipboardMonitor：0.5s 轮询 NSPasteboard         │
│  ├── PasteService：写入剪贴板 + 模拟 Cmd+V             │
│  └── FrequencyCleanupService：启动时按频率清理         │
├─────────────────────────────────────────────────────┤
│  数据层 (SwiftData)                                   │
│  └── ClipItem @Model                                  │
└─────────────────────────────────────────────────────┘
```

### 数据流

1. `ClipboardMonitor` 检测剪贴板变化 → 去重后写入 SwiftData
2. 用户悬停胶囊 → `CapsuleView` 从收起态动画过渡到展开态，列表从 SwiftData 查询
3. 用户点击条目 → `PasteService` 将内容写入剪贴板 → `CGEvent` 模拟 Cmd+V 到前台应用 → 更新该条目 `pasteCount`
4. 应用启动 → `FrequencyCleanupService` 按 `pasteCount` 降序保留 Top 50

---

## 数据模型

```swift
@Model
final class ClipItem {
    var id: UUID
    var timestamp: Date           // 首次捕获时间
    var lastPastedAt: Date?       // 最近粘贴时间
    var pasteCount: Int           // 粘贴次数（频率排序依据）
    var contentTypeRaw: String    // "text" | "image" | "file"
    var textContent: String?      // 纯文本（type=text）
    var imageData: Data?          // 图片 JPEG（type=image，最大 2MB）
    var fileBookmarks: Data?      // 文件路径 bookmark data（type=file）
    var isPinned: Bool            // 置顶标记
    var sourceAppBundleID: String? // 来源应用 bundle ID
}
```

### 存储策略

- **文本**：直接存 `textContent`
- **图片**：JPEG 压缩存 `imageData`，最大 2MB，超过则缩放至合理尺寸
- **文件**：存 security-scoped bookmark data，防止文件移动后失效
- **去重**：新内容与最近一条完全相同 → 不新增，仅更新该条 `timestamp`
- **上限**：总数 200 条，超出时删除 `pasteCount` 最低的非置顶项
- **重启清理**：`ORDER BY isPinned DESC, pasteCount DESC LIMIT 50`
- **置顶项不计入 50 条配额**

---

## UI 设计

### 收起态 — 胶囊条

- 约 36pt 高 × 200pt 宽，圆角胶囊形（corner radius = height / 2）
- 半透明毛玻璃背景（`.ultraThinMaterial`）
- 显示最近一条内容的缩略摘要
- 左侧状态点：绿色空闲 / 蓝色闪烁表示刚捕获新内容（2 秒）
- 始终悬浮在所有窗口之上（`NSWindow.Level.floating`）

### 展开态 — 列表面板

- 约 360pt 高 × 280pt 宽
- 顶部：搜索栏 + 齿轮设置按钮
- 中间：可滚动列表，类型图标 + 内容预览
- 底部：置顶数/总数统计
- 鼠标悬停 0.3 秒展开，移开 1 秒后自动收起

### 交互

- 点击条目直接粘贴（写入剪贴板 → 模拟 Cmd+V）
- 条目悬停时右侧显示删除 ✕ 按钮
- 拖动胶囊条任意位置移动窗口，松手保存位置到 `UserDefaults`
- 搜索栏实时过滤（内容文本 / 文件名匹配）
- 齿轮按钮打开设置面板

---

## 核心服务

### ClipboardMonitor

- 轮询周期：0.5 秒
- 通过 `NSPasteboard.general.changeCount` 检测变化
- 判定类型：`string` → text，`png`/`tiff` → image，`fileURL` → file
- 去重：内容与最近一条完全相同则不重复添加
- 自粘贴过滤：应用自身触发粘贴时跳过

### PasteService

- 根据 `contentType` 将内容写回 `NSPasteboard.general`
- 通过 `CGEvent` 模拟 Cmd+V 到前台应用
- 粘贴动作标记 `isSelfPaste = true`，防止 ClipboardMonitor 误捕获
- 粘贴后不恢复剪贴板原内容（用户点击即意图替换剪贴板）

### FrequencyCleanupService

- 触发时机：App 启动，ModelContainer 初始化完成后
- 查询所有 `ClipItem`，按 `isPinned DESC, pasteCount DESC` 排序
- 保留前 50 条（可配置），删除其余
- 置顶项不计入 50 条配额

---

## 技术要点

- **窗口载体**：`NSPanel` + `NSWindow.Level.floating` + `canJoinAllSpaces`
- **无边框窗口**：隐藏标题栏，自定义拖动区域
- **窗口不抢焦点**：`NSPanel` 默认不激活，用户在其他应用工作时胶囊不夺走键盘焦点
- **窗口位置持久化**：`UserDefaults` 存储 frame 字符串
- **CGEvent 粘贴**：先 `NSWorkspace.shared.frontmostApplication` 获取前台应用，再向其发送 Cmd+V
- **安全范围书签**：文件引用使用 `URL.bookmarkData()` 持久化
