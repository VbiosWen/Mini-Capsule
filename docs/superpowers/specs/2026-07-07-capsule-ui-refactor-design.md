# Capsule UI 重构与功能增强设计

**Date:** 2026-07-07
**Status:** Approved

## Overview

一次性重构悬浮胶囊窗口的全部 UI 组件（设置模块除外），修复所有已知 bug 和 UX 问题，添加新功能增强，并建立完整的自动化功能测试体系。

## Scope

### 重构范围

| 文件 | 动作 | 说明 |
|------|------|------|
| `UI/CapsuleView.swift` | 重构 | 提取状态到 ViewModel，变为纯布局 |
| `UI/CapsuleViewModel.swift` | **新增** | 展开/折叠状态机、hover 计时、拖拽、透明度 |
| `UI/CapsuleExpandedView.swift` | 重构 | 提取列表逻辑到 ViewModel，纯布局 |
| `UI/ClipboardListViewModel.swift` | **新增** | 搜索、过滤、多选、键盘导航 |
| `UI/CapsuleCollapsedView.swift` | 重构 | 新增 icon 样式 |
| `UI/CapsuleWindowController.swift` | 重构 | 只做窗口生命周期，提取拖拽和持久化 |
| `UI/ClipItemRow.swift` | 重构 | 右键菜单、多选模式、popover 编辑入口 |
| `UI/PopoverEditorView.swift` | **新增** | 文本编辑弹窗（持久化修改） |
| `UI/KeyboardEventHandler.swift` | **新增** | 键盘事件处理独立类（从 ExpandedView 提取） |
| `UI/CopyFeedbackView.swift` | **新增** | 复制成功 HUD 反馈 |
| `Settings/SettingsKey.swift` | 扩展 | 新增 capsuleWindowFrame key |
| `Settings/SettingsStore.swift` | 重构 | 升级到 @Observable，新增 capsuleWindowFrame 属性 |
| `Utilities/ColorHex.swift` | **新增** | 从 AppearanceSettingsView 提取 Color(hex:) 扩展 |

### Bugs Fixed (7)

| # | Bug | Fix |
|---|-----|-----|
| B1 | CapsuleWindowController.deinit 不清理 NotificationCenter observer | deinit 中遍历 observers 逐一 removeObserver，取消 cancellables |
| B2 | CapsuleAppDelegate 无 deinit，shortcutMonitor 泄漏 | 新增 deinit 移除 monitor |
| B3 | MenuBarService monitor token 未保存 | start() 中保存 mouseMonitor，stop() 中移除 |
| B4 | Frame 持久化绕过 SettingsStore | capsuleWindowFrame 作为 @AppStorage Data?（JSON 编解码），通过 SettingsStore 读写 |
| B5 | Hover DispatchWorkItem 竞态 | Task + Task.isCancelled 替代，cancel 在 await 点可靠中断 |
| B6 | Color(hex:) 位置不当 | 移至 Utilities/ColorHex.swift |
| B7 | PasteService V 键硬编码 0x09 | 动态查找 V 键 keyCode，备用 TISCopyCurrentKeyboardInputSource + UCKeyTranslate |

### UX Improvements (5)

| # | Issue | Solution |
|---|-------|----------|
| U1 | Escape 不能折叠 | CapsuleViewModel.collapse() 处理：清空搜索 → 退出多选 → 折叠 |
| U2 | Popover 闪烁 | hover 进入 200ms debounce 后才显示 popover |
| U3 | 无复制反馈 | CopyFeedbackView HUD 滑入动画，1.5s 后消失 |
| U4 | 无类型过滤 | 搜索栏下方三个标签："全部"/"文本"/"图片"，切换 filterType |
| U5 | 无法批量删除 | 多选模式 + 底部操作栏"删除所选 (N)" |

### New Features (5)

| # | Feature | Detail |
|---|---------|--------|
| E1 | 拖拽排序 Pinned 项目 | pinned 项支持拖拽重排，ClipItem 新增 sortOrder: Int? |
| E2 | Icon 折叠样式 | 24×24 平台图标，根据最新内容类型显示 📝/🖼️/📁/📋 |
| E3 | 动画优化 | Spring 曲线调优、scale 效果、捕获 bounce、反馈 slideIn+fadeOut |
| E4 | Popover 内文本编辑 | 文本弹窗底部"编辑"按钮 → TextEditor → 保存持久化 |
| E5 | 右键上下文菜单 | 复制、粘贴到前台、置顶/取消、编辑（仅文本）、删除 |

---

## Architecture

### Pattern: MVVM + @Observable

项目部署目标为 macOS 26.5，使用 Swift 5.9+ 的 `@Observable` 宏。`SettingsStore` 从 `@ObservableObject` 升级到 `@Observable`，移除所有 `didSet { objectWillChange.send() }` 样板代码。

### File Structure (Post-Refactor)

```
Mini Capsule/
├── UI/
│   ├── CapsuleView.swift              (重构 — 纯布局)
│   ├── CapsuleViewModel.swift         (新增 — @Observable)
│   ├── CapsuleExpandedView.swift      (重构 — 纯布局)
│   ├── ClipboardListViewModel.swift   (新增 — @Observable)
│   ├── CapsuleCollapsedView.swift     (重构 — dot/capsule/icon 三种样式)
│   ├── CapsuleWindowController.swift  (重构 — 窗口生命周期)
│   ├── ClipItemRow.swift              (重构 — 右键菜单、多选、popover 编辑入口)
│   ├── PopoverEditorView.swift        (新增 — 文本编辑弹窗)
│   ├── KeyboardEventHandler.swift     (新增 — 键盘导航)
│   └── CopyFeedbackView.swift         (新增 — 复制反馈 HUD)
├── Settings/
│   ├── SettingsKey.swift              (扩展 — capsuleWindowFrame)
│   ├── SettingsStore.swift            (重构 — @Observable 升级)
│   └── ... (其余 settings 文件不变)
├── Utilities/
│   └── ColorHex.swift                 (提取 — Color(hex:) 扩展)
├── Services/
│   └── PasteService.swift             (修复 — 动态 keyCode 查找)
└── ...
```

### Drag Monitoring (Clarification)

拖拽监听保留在 `CapsuleWindowController`（需要移动 NSWindow），但拖拽状态（`isDragging`）通过现有通知模式（`.capsuleDragStarted` / `.capsuleDragEnded`）同步到 `CapsuleViewModel`。ViewModel 仅追踪状态以暂时禁用 hover 展开。

### Component Responsibilities

| Component | Single Responsibility |
|-----------|---------------------|
| `CapsuleViewModel` | 展开/折叠状态机、hover Task 计时、拖拽状态、窗口透明度、捕获动画触发 |
| `ClipboardListViewModel` | 搜索过滤、类型筛选、多选集合、批量操作、键盘导航索引、复制/删除/置顶 action |
| `CapsuleView` | 纯布局：消费两个 ViewModel，根据 isExpanded 切换 Expanded/Collapsed |
| `CapsuleExpandedView` | 搜索栏 + 过滤标签 + ScrollView/LazyVStack + 状态栏 |
| `ClipItemRow` | 单行渲染（类型图标、预览文本、时间戳）、右键菜单、hover popover |
| `PopoverEditorView` | 文本编辑 TextEditor + 保存/取消按钮，修改持久化到 SwiftData |
| `KeyboardEventHandler` | NSEvent → ViewModel 的桥接层（NSViewRepresentable），可独立测试 |
| `CapsuleCollapsedView` | dot / capsule / icon 三种折叠样式纯渲染 |
| `CapsuleWindowController` | NSWindow 创建/销毁、frameDidMove 持久化、展开/折叠尺寸与圆角切换 |
| `CopyFeedbackView` | HUD toast 动画，监听 ViewModel.lastCopiedItemID |

### Data Flow

```
SettingsStore (@Observable)
    │
    ├── CapsuleViewModel  (读取: panelOpacityUnfocused, hoverExpandDelay, hoverCollapseDelay, collapsedStyle)
    │
    ├── ClipboardListViewModel (读取: settings, 持有: ModelContext)
    │       │
    │       ├── filteredItems (computed: allItems + searchText + filterType)
    │       ├── selectedItemIDs (Set<UUID>)
    │       └── keyboard navigation index
    │
    └── CapsuleWindowController (读取: capsuleWindowFrame, collapsedStyle)

CapsuleView
    ├── @State CapsuleViewModel
    ├── @State ClipboardListViewModel
    └── @Environment SettingsStore
```

### Key Design Decisions

1. **Task 替代 DispatchWorkItem** — hover 计时的取消在 Swift 并发模型中更可靠（`Task.isCancelled` 在 await 点保证检测），消除竞态
2. **ViewModel 持有 ModelContext** — `ClipboardListViewModel` 直接持有 `ModelContext`（通过 init 注入），避免 View 层传递 context
3. **SettingsStore → @Observable** — 与新增 ViewModel 的模式统一，移除 `ObservableObject` + `didSet` 样板
4. **CapsuleWindowFrame 经 SettingsStore** — 与其他设置一致的访问路径，消除原始 UserDefaults 调用
5. **键盘导航提取为独立类** — `KeyboardEventHandler` 作为 NSViewRepresentable 桥接层，键盘逻辑全在 ViewModel 中，桥接层只做事件转发

---

## Detailed Component Design

### CapsuleViewModel

```
@MainActor @Observable
final class CapsuleViewModel {
    // MARK: Published State
    var isExpanded = false
    var isExpandingReady = false
    var isCapturing = false
    var isDragging = false
    
    // MARK: Dependencies
    let settings: SettingsStore
    
    // MARK: Internal
    private var hoverTask: Task<Void, Never>?
    
    // MARK: Computed
    var windowOpacity: Double {
        isExpanded ? 1.0 : settings.panelOpacityUnfocused
    }
    var expandDelay: Double { settings.hoverExpandDelay }
    var collapseDelay: Double { settings.hoverCollapseDelay }
    
    // MARK: Inputs
    func onHoverEnter()
    func onHoverExit()
    func collapse()            // Escape key handler
    func onDragStart()
    func onDragEnd()
    func onNewItemCaptured()
}
```

**Hover 状态机**（Task 替代 DispatchWorkItem）：

```
onHoverEnter:
    hoverTask?.cancel()
    if isDragging → return
    isExpandingReady = false
    hoverTask = Task {
        await sleep(expandDelay)
        if Task.isCancelled → return
        isExpanded = true
        post notification .capsuleDidChangeExpanded
        await sleep(0.35s)
        isExpandingReady = true
    }

onHoverExit:
    hoverTask?.cancel()
    isExpandingReady = false
    hoverTask = Task {
        await sleep(collapseDelay)
        if Task.isCancelled → return
        isExpanded = false
        post notification .capsuleDidChangeExpanded
    }

collapse():
    hoverTask?.cancel()
    if isExpanded:
        isExpanded = false
        post notification .capsuleDidChangeExpanded
```

### ClipboardListViewModel

```
@MainActor @Observable
final class ClipboardListViewModel {
    // MARK: Filter State
    var searchText = ""
    var filterType: ContentFilter = .all   // all / text / image / file
    
    // MARK: Selection State
    var selectedItemIDs = Set<UUID>()
    var isMultiSelectMode = false
    var lastCopiedItemID: UUID?
    
    // MARK: Dependencies
    let modelContext: ModelContext
    let settings: SettingsStore
    
    // MARK: Actions
    func copyItem(_ item: ClipItem)       // copy + stats + feedback
    func pasteItem(_ item: ClipItem)      // paste to frontmost app
    func deleteItem(_ item: ClipItem)
    func deleteSelected()                 // batch delete
    func togglePin(_ item: ClipItem)
    func editText(_ item: ClipItem, content: String)  // persist edit
    func toggleMultiSelect()
    
    // MARK: Keyboard Navigation
    func moveSelectionUp()
    func moveSelectionDown()
    func confirmSelection()
    func handleEscape()                   // clear search → exit multi → collapse
    func selectAll()
    
    // MARK: Computed
    var filteredItems: [ClipItem]         // allItems filtered by search + type
    var pinnedCount: Int
    var totalCount: Int
}
```

**Escape 键逻辑链**：

```
handleEscape():
    if !searchText.isEmpty → searchText = ""
    else if isMultiSelectMode → exit multi-select
    else → CapsuleViewModel.collapse()
```

**复制反馈**：

```
copyItem(_ item):
    PasteService.copyToClipboard(item)
    item.pasteCount += 1
    item.lastPastedAt = Date()
    item.timestamp = Date()
    modelContext.save()
    lastCopiedItemID = item.id   // triggers CopyFeedbackView
```

### CapsuleCollapsedView — Icon Style

新增第三种 collapsedStyle 值 `"icon"`：

```swift
// 24×24 rounded rect with ultraThinMaterial
ZStack {
    RoundedRectangle(cornerRadius: 6)
        .fill(.ultraThinMaterial)
        .frame(width: 24, height: 24)
    Image(systemName: typeIconName)  // 📝→doc.text, 🖼️→photo, 📁→doc
        .font(.system(size: 14))
}
```

### CapsuleWindowController — 精简后

保留职责：
- 窗口创建（CapsulePanel 初始化）
- 展开/折叠时尺寸 + 圆角切换（响应 `.capsuleDidChangeExpanded`）
- collapsedStyle 变化时更新折叠尺寸/圆角
- 重置位置（响应 `.resetCapsulePosition`）
- Frame 持久化（通过 SettingsStore，不再直读 UserDefaults）
- show/hide 响应（响应 `.showFloatingPanelChanged`）

提取/删除：
- 拖拽监听 → 提取到 CapsuleViewModel（通过 CapsuleView 绑定 drag gesture）
- 直读 UserDefaults → 全部改为 SettingsStore
- 所有 observer 在 deinit 中清理

### ClipItemRow — 右键菜单

```swift
.contextMenu {
    Button("复制") { viewModel.copyItem(item) }
        .keyboardShortcut("c")
    Button("粘贴到前台") { viewModel.pasteItem(item) }
    if item.isPinned {
        Button("取消置顶") { viewModel.togglePin(item) }
    } else {
        Button("置顶") { viewModel.togglePin(item) }
    }
    if item.contentTypeRaw == "text" {
        Button("编辑") { showEditor = true }
    }
    Divider()
    Button("删除", role: .destructive) { viewModel.deleteItem(item) }
        .keyboardShortcut(.delete)
}
```

### PopoverEditorView

文本 item hover 弹窗底部显示"编辑"按钮。点击后在弹窗内展开 TextEditor（预填当前内容），底部保存/取消按钮。保存调用 `viewModel.editText(item, newContent)` 更新 `item.textContent` 并持久化。

### CopyFeedbackView

HUD 半透明条，从胶囊底部滑入：

```
HStack { Image(systemName: "checkmark"); Text("已复制") }
    .padding(.horizontal, 12).padding(.vertical, 6)
    .background(.ultraThinMaterial)
    .clipShape(Capsule())
    .offset(y: isVisible ? 0 : 20)
    .opacity(isVisible ? 1 : 0)
    .animation(.spring(response: 0.3), value: isVisible)
    .onChange(of: viewModel.lastCopiedItemID) {
        isVisible = true
        Task { await sleep(1.5s); isVisible = false }
    }
```

### KeyboardEventHandler

独立的 NSViewRepresentable，接管 ExpandedView 的键盘事件：

```
KeyboardEventHandler (NSViewRepresentable)
├── Coordinator: 弱引用 ClipboardListViewModel
├── makeNSView: 创建 MonitorView，addLocalMonitorForEvents(.keyDown)
├── handleKeyEvent:
│   ├── ↓ (125) → viewModel.moveSelectionDown()
│   ├── ↑ (126) → viewModel.moveSelectionUp()
│   ├── Enter (36/76) → viewModel.confirmSelection()
│   ├── Escape (53) → viewModel.handleEscape()
│   ├── Cmd+A → viewModel.selectAll()
│   └── default → return event (pass through to search field)
└── deinit → removeMonitor
```

---

## Bug Fix Details

### B1: CapsuleWindowController Observer Cleanup

```swift
deinit {
    dragPrimer?.cancel()
    if let monitor = dragMonitor { NSEvent.removeMonitor(monitor) }
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers.removeAll()
    cancellables.removeAll()
}
```

### B2: CapsuleAppDelegate Deinit

```swift
deinit {
    if let monitor = shortcutMonitor { NSEvent.removeMonitor(monitor) }
}
```

### B3: MenuBarService Monitor

```swift
private var mouseMonitor: Any?

func start() {
    mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { ... }
}

func stop() {
    if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    // existing cleanup
}
```

### B4: Frame Persistence via SettingsStore

```swift
// SettingsKey
case capsuleWindowFrame  // Data? (JSON-encoded [String: CGFloat])

// SettingsStore
var capsuleWindowFrame: Data?  // @AppStorage

// CapsuleWindowController
func saveFrame() {
    let dict: [String: CGFloat] = ["x": x, "y": y, "w": w, "h": h]
    settingsStore.capsuleWindowFrame = try? JSONEncoder().encode(dict)
}
func loadFrame() -> NSRect {
    guard let data = settingsStore.capsuleWindowFrame,
          let dict = try? JSONDecoder().decode([String: CGFloat].self, from: data)
    else { return defaultFrame }
    return frame(from: dict)
}
```

### B5: Hover Race Condition

用 Task + Task.isCancelled 替代 DispatchWorkItem（已在 CapsuleViewModel 中详述）。

### B6: Color(hex:) Extraction

`AppearanceSettingsView.swift` 第 146 行的 `extension Color { init?(hex:) }` 移至新文件 `Utilities/ColorHex.swift`。`CapsuleCollapsedView` 和 `AppearanceSettingsView` 都使用该扩展。

### B7: Dynamic KeyCode Lookup

```swift
static func keyCode(for character: Character) -> CGKeyCode {
    // Try CGEventSource API first
    if let source = CGEventSource(stateID: .combinedSessionState) {
        // CGEventSource.keyCode is available in newer SDKs
        let code = CGEventSource.keyCode(
            forKeyboardType: CGEventSource.keyboardType(source) ?? 40,
            source: source,
            character: String(character)
        )
        if code != 0 { return code }
    }
    // Fallback: TISCopyCurrentKeyboardInputSource + UCKeyTranslate
    // Ultimate fallback: 0x09 (QWERTY V)
    return 0x09
}
```

---

## Test Strategy

### Test File Structure

```
Mini CapsuleTests/
├── Mini_CapsuleTests.swift              (现有 — SettingsStore/CapsuleWindowController 测试，扩展)
├── CapsuleViewModelTests.swift          (新增)
├── ClipboardListViewModelTests.swift    (新增)
├── KeyboardEventHandlerTests.swift      (新增)
├── CapsuleWindowControllerTests.swift   (新增 — 独立文件)
├── PasteServiceTests.swift              (新增)
├── ColorHexTests.swift                  (新增)
└── IntegrationTests.swift               (新增 — 跨组件交互)
```

### Test Coverage Checklist

#### ViewModel 层

| # | Test | Target |
|---|------|--------|
| 1 | 初始状态全部为默认值 | CapsuleViewModel |
| 2 | onHoverEnter 延迟后 isExpanded = true | CapsuleViewModel |
| 3 | onHoverEnter 后快速 onHoverExit 不触发展开 | CapsuleViewModel |
| 4 | onHoverExit 延迟后 isExpanded = false | CapsuleViewModel |
| 5 | collapse() 立即折叠 | CapsuleViewModel |
| 6 | onDragStart 后 hover 不响应 | CapsuleViewModel |
| 7 | onDragEnd 恢复 hover 响应 | CapsuleViewModel |
| 8 | onNewItemCaptured 触发捕获动画 | CapsuleViewModel |
| 9 | windowOpacity 展开=1.0 折叠=setting值 | CapsuleViewModel |
| 10 | 搜索过滤：空文本匹配全部 | ClipboardListViewModel |
| 11 | 搜索过滤：部分文本匹配 | ClipboardListViewModel |
| 12 | 搜索过滤：无匹配返回空 | ClipboardListViewModel |
| 13 | filterType all/text/image 过滤 | ClipboardListViewModel |
| 14 | 单选选中/取消 | ClipboardListViewModel |
| 15 | 多选模式进入/退出 | ClipboardListViewModel |
| 16 | selectAll 全选 | ClipboardListViewModel |
| 17 | 批量删除选中项 | ClipboardListViewModel |
| 18 | copyItem 更新 stats 并设 lastCopiedItemID | ClipboardListViewModel |
| 19 | editText 修改 textContent 并持久化 | ClipboardListViewModel |
| 20 | togglePin 切换 isPinned | ClipboardListViewModel |
| 21 | handleEscape 清空搜索→退出多选→折叠 | ClipboardListViewModel |
| 22 | 键盘↑↓移动选中索引 | ClipboardListViewModel |
| 23 | Enter 确认选中项 | ClipboardListViewModel |

#### UI 层

| # | Test | Target |
|---|------|--------|
| 24 | dot 样式渲染圆点 | CapsuleCollapsedView |
| 25 | capsule 样式渲染 HStack | CapsuleCollapsedView |
| 26 | icon 样式渲染图标方块 | CapsuleCollapsedView |
| 27 | dotColorMode auto 按类型着色 | CapsuleCollapsedView |
| 28 | dotColorMode custom 使用自定义色 | CapsuleCollapsedView |
| 29 | ClipItemRow 文本预览截断 | ClipItemRow |
| 30 | ClipItemRow 图片缩略图渲染 | ClipItemRow |
| 31 | PopoverEditor 保存按钮更新内容 | PopoverEditorView |
| 32 | PopoverEditor 取消按钮不修改 | PopoverEditorView |
| 33 | CopyFeedbackView 显示后 1.5s 消失 | CopyFeedbackView |

#### Window Controller

| # | Test | Target |
|---|------|--------|
| 34 | initialCornerRadius 匹配 collapsedStyle | CapsuleWindowController |
| 35 | 展开时 radius=12 | CapsuleWindowController |
| 36 | 折叠恢复样式对应 radius | CapsuleWindowController |
| 37 | resetPosition 清除 frame 数据 | CapsuleWindowController |
| 38 | 通知 removes frame key | CapsuleWindowController |
| 39 | saveFrame 写入 SettingsStore | CapsuleWindowController |
| 40 | loadFrame 读取 SettingsStore | CapsuleWindowController |
| 41 | deinit 清理所有 observers | CapsuleWindowController |

#### Bug 验证

| # | Test | Target |
|---|------|--------|
| 42 | B1: deinit 后无残留 observer | CapsuleWindowController |
| 43 | B2: AppDelegate deinit 移除 shortcutMonitor | CapsuleAppDelegate |
| 44 | B3: MenuBarService stop 移除 mouseMonitor | MenuBarService |
| 45 | B5: 快速 hover in/out/in，最终状态正确 | CapsuleViewModel |
| 46 | B6: Color(hex:) 解析 6 位 hex | ColorHex |
| 47 | B7: keyCode 查找返回非零值（QWERTY） | PasteService |

#### Integration

| # | Test | Target |
|---|------|--------|
| 48 | 完整展开→搜索→选中→复制→折叠流程 | Integration |
| 49 | 多选→批量删除流程 | Integration |
| 50 | 右键菜单→编辑→保存流程 | Integration |

---

## Non-Goals

- 不修改 Settings UI（GeneralSettingsView, AppearanceSettingsView 等）
- 不修改 SwiftData model（ClipItem 仅新增 sortOrder 字段）
- 不修改 iCloud Sync（保持"coming soon"占位）
- 不修改 UI 测试文件
- 不添加第三方依赖
- 不改变设置面板的任何功能行为
