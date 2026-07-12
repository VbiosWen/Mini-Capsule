# CLAUDE.md

Claude Code 使用指南，适用于 Mini Capsule 仓库。

## 最重要的规定

**必须使用中文回复。** 所有对话、解释、代码注释、commit 信息均应使用中文。

## 构建与测试命令

```bash
# macOS 构建（主要目标）
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build

# iOS 模拟器构建
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' build

# 运行单元测试（Swift Testing 框架）
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test

# 运行单个测试
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:Mini_CapsuleTests/ClipboardMonitorTests/nsImageToPNGDataProducesValidPNG test

# 在 Xcode 中打开
open "Mini Capsule.xcodeproj"
```

## 项目定位

Mini Capsule 是一款 **macOS 剪贴板管理器**，提供浮动胶囊 UI。它通过轮询 `NSPasteboard.general` 来捕获剪贴板历史，使用 SwiftData 持久化，支持 Carbon 全局热键快速粘贴。iOS/visionOS target 仅为占位桩代码——实际功能仅在 macOS 上实现（`#if os(macOS)`）。

- **架构：** MVVM + Services，SwiftUI 结合 AppKit 窗口宿主
- **持久化：** SwiftData（数据模型：`ClipItem`、`Item`）
- **剪贴板轮询：** `Timer` 驱动的 `NSPasteboard.changeCount` 差异检测
- **全局热键：** Carbon `RegisterEventHotKey`
- **设置：** JSON 文件存储，通过 `SettingsPersistence` actor 读写，运行时通过 `SettingsStore` 访问
- **测试：** Swift Testing（`@Test`、`#expect`）用于单元测试；XCTest 用于 UI 测试
- **部署目标：** 26.5（iOS、macOS、visionOS）

## 组件关系图

```
Mini_CapsuleApp.swift（App 入口 + CapsuleAppDelegate）
├── SettingsStore ── SettingsPersistence ── SettingsData
├── CapsuleWindowController
│   └── CapsulePanel（NSPanel，canBecomeKey=true）
│       └── CapsuleView（SwiftUI 根视图）
│           ├── CapsuleCollapsedView   ← 悬停 → 展开
│           └── CapsuleExpandedView    ← 280×360 面板
│               ├── KeyboardEventHandler（↑↓ Enter Esc）
│               ├── ClipItemRow ×N（悬停弹出窗口 + 右键菜单）
│               │   └── PopoverEditorView（编辑文本）
│               └── CopyFeedbackView（"已复制" 提示）
├── ClipboardMonitor（Timer → NSPasteboard.poll）
│   └── PasteService（静态：复制/粘贴 + CGEvent Cmd+V）
├── HotKeyCenter（Carbon 全局热键）
├── MenuBarService（NSStatusItem + NSMenu）
└── FrequencyCleanupService（启动时清理）
```

## 核心模式

### 设置系统：协议 + Store + 持久化
- `SettingsProtocol` — 所有消费者依赖的协议（便于测试 mock，可使用 `MockSettings`）
- `SettingsStore` — `@Observable @MainActor` 类，计算属性转发给 `SettingsData`，每次 set 调用 `persist()`，通过 `NotificationCenter` 发送副作用通知（快捷键、样式、轮询间隔）
- `SettingsPersistence` — `actor`，负责 JSON 文件的读写
- 设置视图通过 `@Environment(SettingsStore.self)` 获取，而非单例模式

### 剪贴板监听：轮询 + 自抑制
- `ClipboardMonitor` 通过可配置的 `Timer` 轮询 `NSPasteboard.general.changeCount`
- 检测到变化 → `readPasteboard()`（分层读取：7 种已知 UTI → NSImage 回退 → fileURL → string）
- `PasteService.markSelfPaste()` 设置标记；`shouldSuppress(changeCount:)` 消费该标记——防止自身触发的复制被重复捕获
- 图片使用 MD5 去重；文本与最新项做内容去重

### 图片剪贴板：分层读取（2026-07-08）
- 优先级 1：7 种已知 UTI（png、tiff、jpeg、gif、heic、heif、bmp）的原始数据——保留原始格式，GIF 动画完整
- 优先级 2：`readObjects(forClasses: [NSImage.self])` 回退——覆盖微信等自定义类型，转换为 PNG
- 优先级 3/4：fileURL → string
- `nsImageToPNGData()`：NSImage → TIFF → NSBitmapImageRep → PNG（仅回退时使用）
- `capImageSize()`：超过限制时缩放并重新压缩为 JPEG（所有路径通用）

### 浮动窗口 + 拖拽
- `CapsulePanel` 是 `NSPanel`，使用 `.floating`、`.nonactivatingPanel`、`.canJoinAllSpaces`
- 拖拽：本地 `NSEvent` 监听 `.leftMouseDown/Dragged/Up`，0.5 秒预处理后拖拽才生效
- 窗口位置通过 JSON 持久化在 `settingsStore.capsuleWindowFrame`

### 悬停展开/收起状态机
- `CapsuleViewModel` 管理：`onHoverEnter()` → 延迟 → 展开（弹簧动画）→ 发送 `.capsuleDidChangeExpanded`
- `CapsuleWindowController.observeExpandedState()` 动画化 NSWindow 的尺寸变化，并同步调整圆角
- `isExpandingReady` 用于控制键盘导航，防止动画期间误触

### 组件通信：NotificationCenter
所有跨组件事件均使用 `Notification.Name` 扩展（定义在 `NotificationNames.swift`）：

| 通知 | 发送者 → 接收者 |
|---|---|
| `.pollingIntervalDidChange` | Settings → ClipboardMonitor |
| `.showFloatingPanelChanged` | Settings → CapsuleWindowController、MenuBarService |
| `.capsuleDidChangeExpanded` | CapsuleViewModel → CapsuleWindowController |
| `.capsuleStyleDidChange` | SettingsStore → CapsuleWindowController |
| `.shortcutsDidChange` | SettingsStore → CapsuleAppDelegate |
| `.capsuleDragStarted/Ended` | CapsuleWindowController → CapsuleView |
| `.capsuleDidResignKey` | CapsuleWindowController → CapsuleView |
| `.capsuleEscapePressed` | KeyboardEventHandler → CapsuleExpandedView |
| `.editTextItem` | PopoverEditorView → CapsuleExpandedView |
| `.pasteItemToFront` | ClipItemRow 右键菜单 → CapsuleExpandedView |
| `.togglePinItem` | ClipItemRow 右键菜单 → CapsuleExpandedView |

### 粘贴：CGEvent 模拟
- `PasteService.paste()`：写入 NSPasteboard → `markSelfPaste()` → 发送 `CGEvent` Cmd+V
- 需要辅助功能权限（`AXIsProcessTrustedWithOptions`）
- `keyCodeForV()` 通过 TIS/UCKeyTranslate 动态解析 V 键码，兼容非 QWERTY 键盘

## 数据模型

### ClipItem（核心 — `@Model`）
| 字段 | 类型 | 用途 |
|------|------|------|
| `id` | UUID | 主键 |
| `timestamp` | Date | 最近捕获/复制时间 |
| `lastPastedAt`、`pasteCount` | Date?、Int | 使用统计，用于清理 |
| `contentTypeRaw` | String | "text"、"image"、"file" |
| `textContent` | String? | 文本内容 |
| `imageData` | Data? | 原始图片数据（PNG/GIF 等） |
| `imageFileName`、`imageMD5` | String?、String? | 图片去重与显示名称 |
| `fileBookmarks` | Data? | 文件引用的 NSURL 书签 |
| `isPinned`、`sortOrder` | Bool、Int? | 图钉置顶与手动排序 |
| `sourceAppBundleID` | String? | 来源应用 |

### Item（旧模板 — `@Model`）
仅有一个字段 `timestamp: Date`。Xcode 模板的遗留产物，剪贴板功能未使用。

## 测试

- **单元测试：** Swift Testing（`import Testing`、`@Test`、`#expect`）。测试文件：`*Tests.swift`。
- **UI 测试：** XCTest，位于 `Mini_CapsuleUITests/`。
- **模拟对象：** `SettingsProtocol` 支持依赖注入。创建遵循 `SettingsProtocol` 的 `MockSettings` 类即可——参考 `ClipboardMonitorTests.swift` 中的已有模式。
- **测试中的 SwiftData：** 使用 `ModelConfiguration(isStoredInMemoryOnly: true)`。在测试 schema 中同时注册 `Item` 和 `ClipItem`。
- **PATH 中无 xcodebuild：** 如果 CommandLineTools 是当前开发者目录，请使用完整路径 `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild`。

## 文件索引

| 文件 | 用途 |
|------|------|
| `Mini_CapsuleApp.swift` | App 入口、CapsuleAppDelegate、初始化连接 |
| `ContentView.swift` | iOS/visionOS 占位视图 |
| `Models/ClipItem.swift` | 核心 @Model 实体 |
| `Models/Item.swift` | 旧模板模型 |
| `Services/ClipboardMonitor.swift` | 剪贴板轮询 + 图片捕获 |
| `Services/PasteService.swift` | 复制到剪贴板 + CGEvent 粘贴 |
| `Services/HotKeyCenter.swift` | Carbon 全局热键 |
| `Services/FrequencyCleanupService.swift` | 启动时历史记录清理 |
| `Services/MenuBarService.swift` | NSStatusItem 与最近内容菜单 |
| `UI/CapsuleView.swift` | SwiftUI 根视图 |
| `UI/CapsuleCollapsedView.swift` | 收起状态：圆点/图标/胶囊 |
| `UI/CapsuleExpandedView.swift` | 展开状态：搜索 + 过滤 + 列表 |
| `UI/CapsuleViewModel.swift` | 悬停/拖拽/捕获状态机 |
| `UI/CapsuleWindowController.swift` | NSPanel + NSWindow 管理 |
| `UI/ClipboardListViewModel.swift` | 过滤、增删、键盘导航 |
| `UI/ClipItemRow.swift` | 单行视图 + 弹出窗口 + 右键菜单 |
| `UI/KeyboardEventHandler.swift` | NSViewRepresentable 键盘事件处理 |
| `UI/PopoverEditorView.swift` | 行内文本编辑弹出窗口 |
| `UI/CopyFeedbackView.swift` | "已复制" 提示 |
| `Settings/SettingsData.swift` | 可编码的设置数据结构（含默认值） |
| `Settings/SettingsProtocol.swift` | 依赖注入/测试协议 |
| `Settings/SettingsPersistence.swift` | Actor 化的 JSON 持久化 |
| `Settings/SettingsStore.swift` | @Observable 运行时 + 副作用 |
| `Settings/NotificationNames.swift` | 所有 Notification.Name 扩展 |
| `Settings/GeneralSettingsView.swift` | 通用设置页 |
| `Settings/ClipboardSettingsView.swift` | 剪贴板设置页 |
| `Settings/AppearanceSettingsView.swift` | 外观设置页 |
| `Settings/ShortcutsSettingsView.swift` | 快捷键录制页 |
| `Settings/AdvancedSettingsView.swift` | 导入导出页 |
| `Utilities/ColorHex.swift` | Color ↔ 十六进制转换 |

## 完整符号表：`docs/superpowers/symbol-table.md`
