# Mini Capsule — 符号表 (Symbol Table)

> 自动生成于 2026-07-08，覆盖全部 40 个 Swift 文件。

## 架构层次

```
App Entry (Mini_CapsuleApp.swift)
├── CapsuleAppDelegate (#if macOS)
│   ├── SettingsStore ── SettingsPersistence ── SettingsData
│   ├── CapsuleWindowController
│   │   └── CapsulePanel (NSPanel)
│   │       └── CapsuleView (SwiftUI root)
│   │           ├── CapsuleCollapsedView (收起: dot / icon / capsule)
│   │           └── CapsuleExpandedView (展开: search + filter + list)
│   │               ├── KeyboardEventHandler (↑↓ Enter Esc)
│   │               ├── ClipItemRow (×N, hover popover + context menu)
│   │               │   └── PopoverEditorView (文本编辑)
│   │               └── CopyFeedbackView ("已复制" 动画)
│   ├── ClipboardMonitor (Timer 轮询 NSPasteboard)
│   │   └── PasteService (static: copy/paste + CGEvent)
│   ├── HotKeyCenter (Carbon RegisterEventHotKey)
│   ├── MenuBarService (NSStatusItem + NSMenu)
│   └── FrequencyCleanupService (startup 清理)
└── ContentView (iOS/visionOS fallback)
```

## 模块 1: 数据模型

### `Item.swift` — 模板模型
```
@Model final class Item
  Properties: timestamp: Date
  Methods:   init(timestamp: Date)
Deps: (none)
```

### `Models/ClipItem.swift` — 核心剪贴板条目
```
@Model final class ClipItem
  Properties:
    id: UUID                    timestamp: Date
    lastPastedAt: Date?         pasteCount: Int
    contentTypeRaw: String      textContent: String?
    imageData: Data?            imageFileName: String?
    imageMD5: String?           fileBookmarks: Data?
    isPinned: Bool              sortOrder: Int?
    sourceAppBundleID: String?
  Methods:
    init(id, timestamp, lastPastedAt, pasteCount, contentTypeRaw,
         textContent, imageData, imageFileName, imageMD5,
         fileBookmarks, isPinned, sortOrder, sourceAppBundleID)
Deps: (none)
```

## 模块 2: 核心服务

### `Services/ClipboardMonitor.swift` — 剪贴板监控
```
@MainActor @ObservableObject final class ClipboardMonitor
  Properties:
    settings: SettingsProtocol          timer: Timer?
    lastChangeCount: Int                context: ModelContext?
  Computed:
    currentPollingInterval: TimeInterval  maxImageBytes: Int
    maxHistoryCount: Int                isDedupEnabled: Bool
  Methods:
    init(settings:)                     start(context:)
    stop()                              checkPasteboard() [private]
    readPasteboard(_:types:) -> (type,text,image,bookmarks,fileName)? [private]
    nsImageToPNGData(_:) -> Data        extractFileName(from:types:) -> String? [private]
  Static Methods:
    md5Hash(_:) -> String               enforceCap(context:maxCount:)
Deps: PasteService, ClipItem, SettingsProtocol
```

### `Services/PasteService.swift` — 粘贴引擎
```
@MainActor final class PasteService
  Static Properties:
    suppressedChangeCount: Int? [private]
  Static Methods:
    markSelfPaste()                     shouldSuppress(changeCount:) -> Bool
    keyCodeForV() -> CGKeyCode          copyToClipboard(_: ClipItem)
    paste(_: ClipItem, context:)
Deps: ClipItem, Carbon, CoreGraphics
```

### `Services/HotKeyCenter.swift` — 全局快捷键 (Carbon)
```
enum HotKeyParser
  Static Methods:
    parse(_ shortcut: String) -> (keyCode, modifiers)?
    keyCode(for character: Character) -> UInt32?
  Static Properties:
    table: [Character: UInt32]  [a-z,0-9]

@MainActor final class HotKeyCenter
  Properties:
    refs: [EventHotKeyRef]              actions: [UInt32: () -> Void]
    handler: EventHandlerRef?           nextID: UInt32
    signature: OSType = 'MCPS' [static]
  Methods:
    installHandlerIfNeeded()            register(_:action:)
    unregisterAll()                     deinit
Deps: Carbon.HIToolbox
```

### `Services/FrequencyCleanupService.swift` — 启动清理
```
enum FrequencyCleanupService
  Static Methods:
    performCleanup(context:keepCount?:settings?)
Deps: ClipItem, SettingsProtocol
```

### `Services/MenuBarService.swift` — 菜单栏
```
@MainActor final class MenuBarService: NSObject, NSMenuDelegate
  Properties:
    statusItem: NSStatusItem?           context: ModelContext?
    menu: NSMenu?                       mouseMonitor: Any?
    settings: SettingsProtocol
  Methods:
    init(settings:)                     start(context:)
    stop()                              updateVisibility(_:)
    rebuildMenu() [private]             previewText(for:) -> String [private]
    menuItemClicked(_:) [@objc]         toggleFloatingPanel() [@objc]
    openSettings() [@objc]              quitApp() [@objc]
Deps: PasteService, ClipItem, SettingsProtocol
```

## 模块 3: UI — 窗口和面板

### `UI/CapsuleWindowController.swift` — NSWindow 管理
```
final class CapsulePanel: NSPanel
  Override: canBecomeKey: Bool = true

final class CapsuleWindowController: NSWindowController, NSWindowDelegate
  Properties:
    modelContainer: ModelContainer      settingsStore: SettingsStore
    isExpanded: Bool                    observers: [NSObjectProtocol]
    dragMonitor: Any?                   dragPrimer: DispatchWorkItem?
    isDragActive: Bool                  dragInitialMouse/Origin: NSPoint?
  Static Sizes:
    capsuleCollapsedSize: (200,36)      iconCollapsedSize: (24,24)
    expandedSize: (280,360)             dotCollapsedSize (dynamic)
  Methods:
    init(modelContainer:settingsStore:) showWindow()
    toggleWindow()                      startDragMonitoring() [private]
    observeExpandedState() [private]    windowDidMove(_:)
    windowDidResignKey(_:)              saveFrame() [private]
    loadFrame(style:ringDiameter:frameData:) -> NSRect [static]
Deps: CapsuleView, CapsulePanel, SettingsStore
```

### `UI/CapsuleViewModel.swift` — 胶囊状态机
```
@MainActor @Observable final class CapsuleViewModel
  Properties:
    isExpanded: Bool            isExpandingReady: Bool
    isCapturing: Bool           isDragging: Bool
    settings: SettingsStore
  Computed:
    windowOpacity: Double       expandDelay: Double
    collapseDelay: Double
  Methods:
    init(settings:)             onHoverEnter()
    onHoverExit()               collapse()
    onDragStart()               onDragEnd()
    onNewItemCaptured()         postExpandedNotification() [private]
Deps: SettingsStore
```

### `UI/CapsuleView.swift` — 根视图
```
struct CapsuleView: View
  Properties:
    modelContext: ModelContext [@Environment]
    items: [ClipItem] [@Query]  capsuleVM: CapsuleViewModel [@State]
    listVM: ClipboardListViewModel [@State]
    settings: SettingsStore [@Environment]
  Methods:
    init(modelContext:settings:)
  Body:
    collapsed → CapsuleCollapsedView(...)
    expanded  → CapsuleExpandedView(...)
Deps: CapsuleViewModel, ClipboardListViewModel, CapsuleExpandedView,
      CapsuleCollapsedView, ClipItem, SettingsStore
```

### `UI/CapsuleCollapsedView.swift` — 收起状态
```
struct CapsuleCollapsedView: View
  Properties:
    latestItem: ClipItem?       isCapturing: Bool
    collapsedStyle: String      settings: SettingsStore [@Environment]
  Styles: ringView / iconView / capsuleView
  Preview: text(20 chars) / 🖼️图片 / 📁文件 / 等待复制...
Deps: ClipItem, SettingsStore
```

### `UI/CapsuleExpandedView.swift` — 展开状态 (280×360)
```
struct CapsuleExpandedView: View
  Properties:
    viewModel: ClipboardListViewModel [@Bindable]
    capsuleViewModel: CapsuleViewModel
    isSearchFocused: Bool [@FocusState]
    settings: SettingsStore [@Environment]
  Sections: searchBar / filterTabs / itemList / bottomBar
  Methods:
    filterTab(_:) -> some View
  Notification receivers:
    .capsuleEscapePressed → viewModel.handleEscape()
    .editTextItem → viewModel.editText()
    .pasteItemToFront → viewModel.pasteItem()
    .togglePinItem → viewModel.togglePin()
Deps: ClipboardListViewModel, CapsuleViewModel, ClipItemRow,
      CopyFeedbackView, KeyboardEventHandler, SettingsStore
```

### `UI/ClipboardListViewModel.swift` — 列表逻辑
```
enum ContentFilter: String, CaseIterable
  Cases: all(全部), text(文本), image(图片)
  Computed: systemImage: String

@MainActor @Observable final class ClipboardListViewModel
  Properties:
    searchText: String          filterType: ContentFilter
    selectedItemIDs: Set<UUID>  isMultiSelectMode: Bool
    lastCopiedItemID: UUID?     modelContext: ModelContext
    settings: SettingsStore
  Computed:
    filteredItems: [ClipItem]   pinnedCount: Int
    totalCount: Int
  Methods:
    init(modelContext:settings:)
    copyItem(_:)                pasteItem(_:)
    deleteItem(_:)              deleteSelected()
    togglePin(_:)               editText(_:content:)
    toggleMultiSelect()         moveSelectionUp/Down()
    confirmSelection()          handleEscape()
    selectAll()
Deps: ClipItem, PasteService, SettingsStore, ContentFilter
```

### `UI/ClipItemRow.swift` — 列表行
```
struct ClipItemRow: View
  Properties:
    item: ClipItem, isSelected: Bool, isInteractive: Bool
    isMultiSelectMode: Bool     onTap/onDelete closures
  State:
    isHovering, showPopover, showEditor, isPopoverHovered
  Views:
    typeIcon (36×36 thumbnail / SF Symbol)
    imagePreview(NSImage) → 200×300 scaled
    textPreview(String) → 300×200 monospaced scroll
    contextMenu: 复制 / 粘贴到前台 / 置顶 / 编辑 / 删除
    popover: image/text preview
Deps: ClipItem, PopoverEditorView
```

### `UI/KeyboardEventHandler.swift` — 键盘导航
```
struct KeyboardEventHandler: NSViewRepresentable
  Typealias: NSViewType = MonitorView
  Properties: viewModel: ClipboardListViewModel
  Methods: makeNSView / updateNSView / makeCoordinator

  final class Coordinator
    Properties: viewModel (weak), owner (weak)
    Methods: handleKeyEvent(_:) -> Bool
      Cmd+A → selectAll  |  ↓/↑ → moveSelection  |  Enter → confirm
      Escape → handleEscape() + post .capsuleEscapePressed

  final class MonitorView: NSView
    Properties: monitor: Any?
    deinit: NSEvent.removeMonitor
Deps: ClipboardListViewModel
```

### `UI/PopoverEditorView.swift` — 文本编辑弹窗
```
struct PopoverEditorView: View
  Properties:
    item: ClipItem             onSave: (String) -> Void
    editedText: String [@State]  isFocused: Bool [@FocusState]
  Body: TextEditor + 取消/保存 buttons, 280pt width
Deps: ClipItem
```

### `UI/CopyFeedbackView.swift` — 复制反馈动画
```
struct CopyFeedbackView: View
  Properties: viewModel: ClipboardListViewModel
  State: isVisible, feedbackTask
  Behavior: 监听 viewModel.lastCopiedItemID, 显示 1.5s
  Body: "✓ 已复制" + 弹簧动画
Deps: ClipboardListViewModel
```

## 模块 4: Settings 系统

### `Settings/SettingsData.swift` — 数据载体
```
struct SettingsData: Codable, Equatable
  Properties (all with defaults):
    historyMaxCount=200  imageMaxSizeMB=2  pollingInterval=0.5
    cleanupOnStartup=true  dedupEnabled=true
    showHideShortcut="cmd+shift+v"  quickPasteShortcut="cmd+shift+c"
    togglePinShortcut=""  iCloudSyncEnabled=false
    launchAtLogin=false  showInMenuBar=true  showFloatingPanel=true
    collapsedStyle="capsule"  hoverExpandDelay=0.3
    hoverCollapseDelay=1.0  panelOpacityUnfocused=0.6
    backgroundImageData=Data()  ringDiameter=30
    capsuleWindowFrame=Data()
  Extension: tolerant CodingKeys init(from:)
Deps: (none)
```

### `Settings/SettingsProtocol.swift` — 协议抽象
```
protocol SettingsProtocol: AnyObject
  (mirrors SettingsData + resetAll/exportData/importData/clearAllHistory)
Deps: SwiftData (ModelContext)
```

### `Settings/SettingsPersistence.swift` — JSON 磁盘持久化
```
actor SettingsPersistence
  Properties: fileURL: URL [private]
  Methods:
    init()                    load() -> SettingsData
    save(_: SettingsData) throws
Deps: SettingsData
```

### `Settings/SettingsStore.swift` — 运行时 + 通知
```
@MainActor @Observable final class SettingsStore: SettingsProtocol
  Properties:
    data: SettingsData [private]    persistence: SettingsPersistence [private]
    (all SettingsData fields as computed get/set → persist())
  Side effects on set:
    shortcut fields → post .shortcutsDidChange
    collapsedStyle/ringDiameter → post .capsuleStyleDidChange
    pollingInterval → post .pollingIntervalDidChange
  Methods: replaceData, resetAll, exportData, importData, clearAllHistory
  Private: ClipItemExport (Codable helper)
Deps: SettingsData, SettingsPersistence, ClipboardMonitor.md5Hash, ClipItem
```

### `Settings/NotificationNames.swift` — 通知名注册
```
extension Notification.Name:
  系统级: .pollingIntervalDidChange, .showFloatingPanelChanged
  胶囊级: .capsuleDidChangeExpanded, .capsuleDragStarted/Ended,
          .resetCapsulePosition, .capsuleDidResignKey, .capsuleEscapePressed
  列表级: .editTextItem, .pasteItemToFront, .togglePinItem
  Settings: .capsuleStyleDidChange, .shortcutsDidChange
Deps: (none)
```

### Settings Views (5 个)
| View | 功能 |
|------|------|
| `GeneralSettingsView` | 启动项、浮动面板、菜单栏、位置重置 |
| `ClipboardSettingsView` | 历史数量、图片大小、去重、轮询间隔 |
| `AppearanceSettingsView` | 收起样式、透明度、环直径、背景图 |
| `ShortcutsSettingsView` + `ShortcutCaptureManager` | 快捷键录制（NSEvent monitor） |
| `AdvancedSettingsView` | 导入/导出、清空历史 |

所有 Settings View 通过 `@Environment(SettingsStore.self)` 注入。

## 模块 5: 工具类

### `Utilities/ColorHex.swift`
```
extension Color:
  init?(hex: String)          func toHex() -> String
Deps: AppKit (NSColor)
```

## 模块 6: App 入口

### `Mini_CapsuleApp.swift`
```
@main struct Mini_CapsuleApp: App
  #if os(macOS):
    @NSApplicationDelegateAdaptor var appDelegate: CapsuleAppDelegate
  #else:
    sharedModelContainer (inMemory fallback)

@MainActor class CapsuleAppDelegate: NSObject, NSApplicationDelegate
  Properties:
    sharedModelContainer (static, ModelContainer, schema=[Item, ClipItem])
    settingsStore: SettingsStore  capsuleWindowController: CapsuleWindowController?
    clipboardMonitor: ClipboardMonitor?  hotKeyCenter: HotKeyCenter
    menuBarService: MenuBarService?
  Methods:
    applicationDidFinishLaunching → finishSetup()
    finishSetup(): start monitor, register hotkeys, setup menu bar, cleanup
    registerShortcuts(): parse → HotKeyCenter.register
    performQuickPaste(): find latest item → PasteService.paste
    performTogglePin(): find latest item → toggle pin
    applicationWillTerminate: stop monitor + menu bar
Deps: ALL services, models, settings
```

## 通知事件映射

| Notification | Sender → Consumer |
|---|---|
| `.pollingIntervalDidChange` | ClipboardSettingsView → ClipboardMonitor |
| `.showFloatingPanelChanged` | GeneralSettingsView → CapsuleWindowController, MenuBarService |
| `.capsuleDidChangeExpanded` | CapsuleViewModel → CapsuleWindowController |
| `.capsuleStyleDidChange` | SettingsStore → CapsuleWindowController |
| `.resetCapsulePosition` | GeneralSettingsView → CapsuleWindowController |
| `.shortcutsDidChange` | SettingsStore → CapsuleAppDelegate |
| `.capsuleDragStarted/Ended` | CapsuleWindowController → CapsuleView |
| `.capsuleDidResignKey` | CapsuleWindowController → CapsuleView |
| `.capsuleEscapePressed` | KeyboardEventHandler → CapsuleExpandedView |
| `.editTextItem` | PopoverEditorView → CapsuleExpandedView |
| `.pasteItemToFront` | ClipItemRow → CapsuleExpandedView |
| `.togglePinItem` | ClipItemRow → CapsuleExpandedView |

## 数据流

```
[外部 App 复制]
  → NSPasteboard.general (changeCount++)
  → ClipboardMonitor timer 轮询 (0.5s)
    → checkPasteboard()
      → readPasteboard(): 7种UTI → NSImage兜底 → fileURL → string
      → MD5 去重 / enforceCap
      → ClipItem.insert → SwiftData.save
    → CapsuleViewModel.onNewItemCaptured() → 2s 动画

[用户粘贴]
  → ClipItemRow.onTap → ClipboardListViewModel.copyItem()
    → PasteService.copyToClipboard() → NSPasteboard + markSelfPaste
  → 或 contextMenu "粘贴到前台"
    → PasteService.paste() → CGEvent Cmd+V → markSelfPaste
```

## 完整依赖图

| 类型 | 依赖 |
|------|------|
| `Mini_CapsuleApp` | 所有服务、模型、Settings |
| `ClipItem`, `Item` | (none) |
| `ClipboardMonitor` | `PasteService`, `ClipItem`, `SettingsProtocol` |
| `PasteService` | `ClipItem` |
| `HotKeyCenter`, `HotKeyParser` | (none) |
| `FrequencyCleanupService` | `ClipItem`, `SettingsProtocol` |
| `MenuBarService` | `PasteService`, `ClipItem`, `SettingsProtocol` |
| `CapsuleWindowController` | `CapsuleView`, `CapsulePanel`, `SettingsStore` |
| `CapsuleView` | `CapsuleViewModel`, `ClipboardListViewModel`, `CapsuleExpandedView`, `CapsuleCollapsedView` |
| `CapsuleCollapsedView` | `ClipItem`, `SettingsStore` |
| `CapsuleExpandedView` | `ClipboardListViewModel`, `CapsuleViewModel`, `ClipItemRow`, `CopyFeedbackView`, `KeyboardEventHandler` |
| `CapsuleViewModel` | `SettingsStore` |
| `ClipboardListViewModel` | `ClipItem`, `PasteService`, `SettingsStore` |
| `ClipItemRow` | `ClipItem`, `PopoverEditorView` |
| `KeyboardEventHandler` | `ClipboardListViewModel` |
| `PopoverEditorView` | `ClipItem` |
| `CopyFeedbackView` | `ClipboardListViewModel` |
| `SettingsStore` | `SettingsData`, `SettingsPersistence`, `ClipItem`, `ClipboardMonitor` |
| `SettingsPersistence` | `SettingsData` |
| `ColorHex` | (none) |
