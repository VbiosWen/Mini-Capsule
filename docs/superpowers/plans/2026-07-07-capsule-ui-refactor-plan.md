# Capsule UI 重构与功能增强 — 实现计划

> **For agentic workers:** 使用 sub-agent 方式执行，每任务独立 agent，无需用户确认。

**Goal:** 一次性重构悬浮胶囊窗口全部 UI 组件（MVVM + @Observable），修复 7 个 bug，实现 5 个 UX 改进，添加 5 个新功能，编写全面自动化测试。

**Architecture:** MVVM + @Observable 宏。新增 CapsuleViewModel（展开/折叠状态机、hover 计时、拖拽状态）和 ClipboardListViewModel（搜索、过滤、多选、键盘导航、复制/删除/置顶操作）。SettingsStore 从 @ObservableObject 升级到 @Observable。NSEvent 监听器统一提取为独立组件。

**Tech Stack:** Swift 5.9+, SwiftUI, SwiftData, AppKit, @Observable, Swift Testing framework

## Global Constraints

- 部署目标: macOS 26.5, iOS 26.5, visionOS 26.5
- 不修改 Settings UI（GeneralSettingsView, AppearanceSettingsView 等）
- 不修改 SwiftData model（ClipItem 仅新增 sortOrder 字段）
- 不修改 iCloud Sync（保持"coming soon"占位）
- 不修改 UI 测试文件
- 不添加第三方依赖
- 不改变设置面板的任何功能行为
- 使用 Task + Task.isCancelled 替代 DispatchWorkItem 做 hover 计时
- Color(hex:) 扩展移至 Utilities/ColorHex.swift
- Frame 持久化通过 SettingsStore.capsuleWindowFrame（Data?，JSON 编解码）

---

### Task 1: 提取 Color(hex:) 到独立工具文件 (B6)

**Files:**
- Create: `Mini Capsule/Utilities/ColorHex.swift`
- Modify: `Mini Capsule/Settings/AppearanceSettingsView.swift:144-167`
- Modify: `Mini Capsule.xcodeproj` (add new file to target)

**Interfaces:**
- Produces: `extension Color { init?(hex: String); func toHex() -> String }` in global scope

- [ ] **Step 1: 创建 Utilities/ColorHex.swift**

Create directory `Mini Capsule/Utilities/` and file `ColorHex.swift`:

```swift
// Mini Capsule/Utilities/ColorHex.swift
import SwiftUI
import AppKit

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        guard hex.count == 6,
              let num = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: Double((num >> 16) & 0xFF) / 255.0,
            green: Double((num >> 8) & 0xFF) / 255.0,
            blue: Double(num & 0xFF) / 255.0
        )
    }

    func toHex() -> String {
        guard let components = NSColor(self).cgColor.components, components.count >= 3 else {
            return "#007AFF"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
```

- [ ] **Step 2: 从 AppearanceSettingsView.swift 删除 Color 扩展**

Remove lines 144-167 from `Mini Capsule/Settings/AppearanceSettingsView.swift` (the entire `// MARK: - Color Extensions` section and the `extension Color` block).

- [ ] **Step 3: 将新文件添加到 Xcode 项目**

Add `ColorHex.swift` to the `Mini Capsule` target in the Xcode project. Use the Ruby xcodeproj gem:

```bash
ruby -e "
require 'xcodeproj'
project = Xcodeproj::Project.open('Mini Capsule.xcodeproj')
target = project.targets.find { |t| t.name == 'Mini Capsule' }
group = project.main_group.find_subpath('Mini Capsule/Utilities', true)
file_ref = group.new_file('ColorHex.swift')
target.source_build_phase.add_file_reference(file_ref)
project.save
puts 'Added ColorHex.swift to Mini Capsule target'
"
```

If Ruby xcodeproj is not available, manually add the file in Xcode: Right-click `Mini Capsule` group → New Group "Utilities" → Add Files to "Utilities" → select `ColorHex.swift`.

- [ ] **Step 4: 构建验证**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 5: 提交**

```bash
git add "Mini Capsule/Utilities/ColorHex.swift" "Mini Capsule/Settings/AppearanceSettingsView.swift" "Mini Capsule.xcodeproj/project.pbxproj"
git commit -m "refactor: extract Color(hex:) extension to Utilities/ColorHex.swift (B6)"
```

---

### Task 2: 扩展 SettingsKey + SettingsStore 添加 capsuleWindowFrame (B4 基础)

**Files:**
- Modify: `Mini Capsule/Settings/SettingsKey.swift:36-37` — 将 `capsuleWindowFrameKey` 从 static let 改为 case
- Modify: `Mini Capsule/Settings/SettingsStore.swift` — 添加 `capsuleWindowFrame` @AppStorage 属性

**Interfaces:**
- Consumes: SettingsKey enum
- Produces: `SettingsStore.capsuleWindowFrame: Data?` (JSON-encoded `[String: CGFloat]`)

- [ ] **Step 1: 将 capsuleWindowFrame 加入 SettingsKey enum**

In `SettingsKey.swift`, replace the static let with a case:

```swift
// Before (line 36-37):
    /// Window frame position persistence key (not a setting, but a shared constant).
    static let capsuleWindowFrameKey = "CapsuleWindowFrame"

// After:
    /// Window frame position persistence key (JSON-encoded [String: CGFloat]).
    case capsuleWindowFrame
```

Then update `allCases` — the enum is `CaseIterable` so the new case is automatically included.

- [ ] **Step 2: 在 SettingsStore 中添加 capsuleWindowFrame 属性**

Add after the existing `dotCustomColor` property (around line 85 in current SettingsStore.swift):

```swift
@AppStorage(SettingsKey.capsuleWindowFrame.rawValue)
var capsuleWindowFrame: Data = Data() { didSet { objectWillChange.send() } }
```

Add to `resetAll()` method, after `dotCustomColor = "#007AFF"`:

```swift
capsuleWindowFrame = Data()
```

- [ ] **Step 3: 更新现有引用从 static let 改为 case rawValue**

In `CapsuleWindowController.swift`, find all uses of `SettingsKey.capsuleWindowFrameKey` and replace with `SettingsKey.capsuleWindowFrame.rawValue`. There are currently 3 locations:
- `saveFrame()`: `UserDefaults.standard.set(..., forKey: SettingsKey.capsuleWindowFrameKey)` → will be refactored in Task 12
- `loadFrame()`: `UserDefaults.standard.dictionary(forKey: SettingsKey.capsuleWindowFrameKey)` → will be refactored in Task 12
- Reset observer: `UserDefaults.standard.removeObject(forKey: SettingsKey.capsuleWindowFrameKey)` → will be refactored in Task 12

For now, update only the key reference strings to use `.rawValue`.

- [ ] **Step 4: 更新 SettingsKeyTests**

In `Mini CapsuleTests/SettingsKeyTests.swift`, update the expected key count and add the new case:

```swift
@Test func allCasesContainsCapsuleWindowFrame() async throws {
    let keys = SettingsKey.allCases.map(\.rawValue)
    #expect(keys.contains("capsuleWindowFrame"))
}
```

- [ ] **Step 5: 构建并运行测试**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 6: 提交**

```bash
git add "Mini Capsule/Settings/SettingsKey.swift" "Mini Capsule/Settings/SettingsStore.swift" "Mini Capsule/UI/CapsuleWindowController.swift" "Mini CapsuleTests/SettingsKeyTests.swift"
git commit -m "feat: add capsuleWindowFrame key to SettingsKey + SettingsStore (B4)"
```

---

### Task 3: SettingsStore 升级 — @ObservableObject → @Observable

**Files:**
- Modify: `Mini Capsule/Settings/SettingsStore.swift` — 完整的类重写
- Modify: `Mini Capsule/Settings/SettingsProtocol.swift` — 新增 capsuleWindowFrame
- Modify: `Mini Capsule/Mini_CapsuleApp.swift` — 调整注入方式
- Modify: 所有使用 `@EnvironmentObject var settings: SettingsStore` 的 View 文件

**Interfaces:**
- Consumes: SettingsKey enum (all cases)
- Produces: `@MainActor @Observable final class SettingsStore: SettingsProtocol`

- [ ] **Step 1: 更新 SettingsProtocol 添加 capsuleWindowFrame**

In `SettingsProtocol.swift`, add under `var dotCustomColor: String { get set }`:

```swift
var capsuleWindowFrame: Data { get set }
```

This ensures all SettingsProtocol conformers expose the frame data.

- [ ] **Step 2: 重写 SettingsStore 为 @Observable**

Replace the entire `SettingsStore.swift`. Key changes:
- `@MainActor @Observable final class SettingsStore: SettingsProtocol` (remove `ObservableObject` conformance)
- Remove all `{ didSet { objectWillChange.send() } }` from every property
- Remove `import Combine` (no longer needed for ObservableObject)
- Keep `@AppStorage(...)` wrapper on every property
- Keep all methods: `resetAll()`, `exportData()`, `importData()`, `clearAllHistory()`

Complete new file content:

```swift
// Mini Capsule/Settings/SettingsStore.swift
import SwiftUI
import SwiftData
import Foundation

/// Export/import DTO for ClipItem serialization.
private struct ClipItemExport: Codable {
    let type: String
    let content: String?
    let fileName: String?
    let timestamp: Date
    let pasteCount: Int
    let sourceApp: String?
}

@MainActor
@Observable
final class SettingsStore: SettingsProtocol {
    // MARK: - Clipboard

    @AppStorage(SettingsKey.historyMaxCount.rawValue)
    var historyMaxCount: Int = 200

    @AppStorage(SettingsKey.imageMaxSizeMB.rawValue)
    var imageMaxSizeMB: Int = 2

    @AppStorage(SettingsKey.pollingInterval.rawValue)
    var pollingInterval: Double = 0.5

    @AppStorage(SettingsKey.cleanupOnStartup.rawValue)
    var cleanupOnStartup: Bool = true

    @AppStorage(SettingsKey.dedupEnabled.rawValue)
    var dedupEnabled: Bool = true

    // MARK: - Shortcuts

    @AppStorage(SettingsKey.showHideShortcut.rawValue)
    var showHideShortcut: String = "cmd+shift+V"

    @AppStorage(SettingsKey.quickPasteShortcut.rawValue)
    var quickPasteShortcut: String = "cmd+shift+C"

    @AppStorage(SettingsKey.togglePinShortcut.rawValue)
    var togglePinShortcut: String = ""

    // MARK: - Advanced

    @AppStorage(SettingsKey.iCloudSyncEnabled.rawValue)
    var iCloudSyncEnabled: Bool = false

    // MARK: - General

    @AppStorage(SettingsKey.launchAtLogin.rawValue)
    var launchAtLogin: Bool = false

    @AppStorage(SettingsKey.showInMenuBar.rawValue)
    var showInMenuBar: Bool = true

    @AppStorage(SettingsKey.showFloatingPanel.rawValue)
    var showFloatingPanel: Bool = true

    @AppStorage(SettingsKey.collapsedStyle.rawValue)
    var collapsedStyle: String = "capsule"

    @AppStorage(SettingsKey.hoverExpandDelay.rawValue)
    var hoverExpandDelay: Double = 0.3

    @AppStorage(SettingsKey.hoverCollapseDelay.rawValue)
    var hoverCollapseDelay: Double = 1.0

    // MARK: - Appearance

    @AppStorage(SettingsKey.panelOpacityUnfocused.rawValue)
    var panelOpacityUnfocused: Double = 0.6

    @AppStorage(SettingsKey.backgroundImageData.rawValue)
    var backgroundImageData: Data = Data()

    @AppStorage(SettingsKey.dotColorMode.rawValue)
    var dotColorMode: String = "auto"

    @AppStorage(SettingsKey.dotCustomColor.rawValue)
    var dotCustomColor: String = "#007AFF"

    // MARK: - Window Frame

    @AppStorage(SettingsKey.capsuleWindowFrame.rawValue)
    var capsuleWindowFrame: Data = Data()

    // MARK: - Actions

    func resetAll() {
        historyMaxCount = 200
        imageMaxSizeMB = 2
        pollingInterval = 0.5
        cleanupOnStartup = true
        dedupEnabled = true
        showHideShortcut = "cmd+shift+V"
        quickPasteShortcut = "cmd+shift+C"
        togglePinShortcut = ""
        iCloudSyncEnabled = false
        launchAtLogin = false
        showInMenuBar = true
        showFloatingPanel = true
        collapsedStyle = "capsule"
        hoverExpandDelay = 0.3
        hoverCollapseDelay = 1.0
        panelOpacityUnfocused = 0.6
        backgroundImageData = Data()
        dotColorMode = "auto"
        dotCustomColor = "#007AFF"
        capsuleWindowFrame = Data()
    }

    func exportData(context: ModelContext) -> Data? {
        let descriptor = FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.timestamp)])
        guard let items = try? context.fetch(descriptor) else { return nil }
        let exports: [ClipItemExport] = items.map { item in
            var content: String?
            if item.contentTypeRaw == "image", let imageData = item.imageData {
                content = imageData.base64EncodedString()
            } else {
                content = item.textContent
            }
            return ClipItemExport(
                type: item.contentTypeRaw, content: content,
                fileName: item.imageFileName, timestamp: item.timestamp,
                pasteCount: item.pasteCount, sourceApp: item.sourceAppBundleID
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(exports)
    }

    func importData(_ data: Data, context: ModelContext) throws {
        let decoder = JSONDecoder()
        let imports = try decoder.decode([ClipItemExport].self, from: data)
        let existingDescriptor = FetchDescriptor<ClipItem>(sortBy: [])
        let existingItems = (try? context.fetch(existingDescriptor)) ?? []
        let existingTexts = Set(existingItems.compactMap { $0.textContent })
        let existingMD5s = Set(existingItems.compactMap { $0.imageMD5 })
        for item in imports {
            switch item.type {
            case "text":
                guard let text = item.content, !existingTexts.contains(text) else { continue }
                context.insert(ClipItem(timestamp: item.timestamp, pasteCount: item.pasteCount,
                    contentTypeRaw: "text", textContent: text, sourceAppBundleID: item.sourceApp))
            case "image":
                guard let base64 = item.content, let imageData = Data(base64Encoded: base64) else { continue }
                let md5 = ClipboardMonitor.md5Hash(imageData)
                guard !existingMD5s.contains(md5) else { continue }
                context.insert(ClipItem(timestamp: item.timestamp, pasteCount: item.pasteCount,
                    contentTypeRaw: "image", imageData: imageData, imageFileName: item.fileName,
                    imageMD5: md5, sourceAppBundleID: item.sourceApp))
            default: continue
            }
        }
        try context.save()
    }

    func clearAllHistory(context: ModelContext) {
        let descriptor = FetchDescriptor<ClipItem>(sortBy: [])
        guard let items = try? context.fetch(descriptor) else { return }
        for item in items { context.delete(item) }
        try? context.save()
    }
}
```

- [ ] **Step 3: 更新 CapsuleAppDelegate 注入方式**

In `Mini_CapsuleApp.swift`, the `Settings` scene uses `.environmentObject(appDelegate.settingsStore)`. With `@Observable`, `@EnvironmentObject` is no longer the right pattern — use `.environment(appDelegate.settingsStore)` instead, and consumers use `@Environment(SettingsStore.self)`.

Wait — actually, `@Observable` classes can still be used with `.environmentObject()` and `@EnvironmentObject` for backward compatibility. But the modern approach is `.environment()` and `@Environment()`. However, this would change all consumers.

**Decision: Keep using `.environmentObject()` for now** — it still works with `@Observable` in macOS 26.5. This minimizes scope. The ViewModels and views that NEED @Observable can use `@Environment(SettingsStore.self)` when created in later tasks.

So for this task, **no changes to CapsuleAppDelegate.swift are needed** — `@Observable` + `@EnvironmentObject` works.

- [ ] **Step 4: 更新现有测试以匹配 @Observable**

In `Mini_CapsuleTests/Mini_CapsuleTests.swift`, the `propertyChangeNotifiesObjectWillChange` test (lines 165-173) references `store.objectWillChange.sink`. With `@Observable`, `objectWillChange` is no longer available directly. Update this test:

Replace the test with one using `withObservationTracking`:

```swift
@Test func propertyChangeIsObservable() async throws {
    let store = SettingsStore()
    store.pollingInterval = 1.5
    // @Observable tracks changes automatically — no explicit objectWillChange needed
    #expect(store.pollingInterval == 1.5)
    store.resetAll()
}
```

- [ ] **Step 5: 构建并运行测试**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test 2>&1 | grep -E "(Test|PASS|FAIL|BUILD)"
```

Expected: all existing tests pass.

- [ ] **Step 6: 提交**

```bash
git add "Mini Capsule/Settings/SettingsStore.swift" "Mini Capsule/Settings/SettingsProtocol.swift" "Mini CapsuleTests/Mini_CapsuleTests.swift"
git commit -m "refactor: upgrade SettingsStore from @ObservableObject to @Observable"
```

---

### Task 4: ClipItem 新增 sortOrder 字段 (E1 基础)

**Files:**
- Modify: `Mini Capsule/Models/ClipItem.swift`

**Interfaces:**
- Produces: `ClipItem.sortOrder: Int?` — non-nil only for pinned items, used for drag reorder

- [ ] **Step 1: 添加 sortOrder 属性**

In `ClipItem.swift`, add after `isPinned` property declaration:

```swift
var isPinned: Bool
var sortOrder: Int?  // NEW: non-nil for pinned items, nil for unpinned

var sourceAppBundleID: String?
```

- [ ] **Step 2: 更新 init 方法**

Add `sortOrder: Int? = nil` parameter to the init, after `isPinned: Bool = false`:

```swift
init(
    ...
    isPinned: Bool = false,
    sortOrder: Int? = nil,    // NEW
    sourceAppBundleID: String? = nil
) {
    ...
    self.isPinned = isPinned
    self.sortOrder = sortOrder  // NEW
    self.sourceAppBundleID = sourceAppBundleID
}
```

- [ ] **Step 3: 构建验证**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 4: 提交**

```bash
git add "Mini Capsule/Models/ClipItem.swift"
git commit -m "feat: add sortOrder property to ClipItem for pinned item reordering (E1)"
```

---

### Task 5: 修复 B7 — PasteService 动态 KeyCode

**Files:**
- Modify: `Mini Capsule/Services/PasteService.swift:84-86`

**Interfaces:**
- Produces: `PasteService.vKeyCode: CGKeyCode` — dynamically resolved

- [ ] **Step 1: 重写 keyCode 查找**

Replace the hardcoded V key (0x09) with dynamic lookup. In `PasteService.swift`, replace lines 82-86 (the comment and keyCode declarations):

```swift
// Before:
        // Note: CGEventSource.keyCode(forKeyboardType:source:character:) is not available
        // in this SDK version. The hardcoded key code 0x09 (V) is QWERTY-specific.
        // For non-QWERTY layouts, a keyboard layout lookup would be needed.
        let cmdKey: CGKeyCode = 0x37
        let vKey: CGKeyCode = 0x09

// After:
        let cmdKey: CGKeyCode = 0x37
        let vKey: CGKeyCode = Self.keyCodeForV()
```

- [ ] **Step 2: 添加静态方法 keyCodeForV()**

Add to `PasteService` class (after the `static var isSelfPaste`):

```swift
    /// Dynamically resolve the key code for the "V" character,
    /// falling back to QWERTY 0x09 if lookup fails.
    static func keyCodeForV() -> CGKeyCode {
        if let source = CGEventSource(stateID: .combinedSessionState) {
            let keyboardType = CGEventSource.keyboardType(source) ?? 40
            let code = CGEventSource.keyCode(
                forKeyboardType: keyboardType,
                source: source,
                character: "v"
            )
            if code != 0 { return code }
        }
        return 0x09 // QWERTY V — ultimate fallback
    }
```

Wait — `CGEventSource.keyCode(forKeyboardType:source:character:)` might not be available in the SDK being used. The existing code comment says it's not available. Let me check what APIs are actually available.

Actually, since the project targets macOS 26.5, the API should be available. But if it's not, we need a fallback using `TISCopyCurrentKeyboardInputSource` + `UCKeyTranslate`. Let me provide both approaches:

```swift
    /// Dynamically resolve the key code for the "V" character.
    /// Uses CGEventSource API (macOS 14+), falls back to QWERTY 0x09.
    static func keyCodeForV() -> CGKeyCode {
        // Try CGEventSource API (available in newer SDKs)
        if let source = CGEventSource(stateID: .combinedSessionState) {
            let keyboardType = CGEventSource.keyboardType(source) ?? 40
            let code = CGEventSource.keyCode(
                forKeyboardType: keyboardType,
                source: source,
                character: "v"
            )
            if code != 0 { return code }
        }
        // Fallback: TIS + UCKeyTranslate for non-QWERTY layouts
        if let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let layoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) {
            let keyboardLayout = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
            var deadKeyState: UInt32 = 0
            let uniChar: [UniChar] = [UniChar(Character("v").unicodeScalars.first?.value ?? 0x0076)]
            var keyCode: UInt32 = 0
            // Iterate through possible key codes
            for kc in 0..<128 as UInt32 {
                let length = keyboardLayout.withUnsafeBytes { ptr -> Int in
                    guard let base = ptr.baseAddress else { return 0 }
                    return Int(UCKeyTranslate(
                        base.assumingMemoryBound(to: UCKeyboardLayout.self),
                        UInt16(kc),
                        UInt16(kUCKeyActionDown),
                        0,
                        UInt32(LMGetKbdType()),
                        UInt32(kUCKeyTranslateNoDeadKeysMask),
                        &deadKeyState,
                        1,
                        &keyCode,
                        nil
                    ))
                }
                if length == 0 { continue }
                if keyCode == uniChar[0] { return CGKeyCode(kc) }
            }
        }
        return 0x09 // QWERTY V — ultimate fallback
    }
```

- [ ] **Step 3: 添加必要的 import**

At the top of `PasteService.swift`, add:
```swift
import Carbon
```

(for `TISCopyCurrentKeyboardInputSource`, `UCKeyTranslate`, `LMGetKbdType`)

- [ ] **Step 4: 构建验证**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 5: 提交**

```bash
git add "Mini Capsule/Services/PasteService.swift"
git commit -m "fix: use dynamic keyCode lookup for V key instead of hardcoded 0x09 (B7)"
```

---

### Task 6: 修复 B1 + B2 + B3 — Observer/Monitor 泄漏

**Files:**
- Modify: `Mini Capsule/UI/CapsuleWindowController.swift:79-83`
- Modify: `Mini Capsule/Mini_CapsuleApp.swift:129-132`
- Modify: `Mini Capsule/Services/MenuBarService.swift:28-37, 49-53`

**Interfaces:**
- Produces: clean deinit in all three classes

- [ ] **Step 1: B1 — CapsuleWindowController deinit 清理所有 observer**

Replace current deinit (lines 79-83):

```swift
// Before:
    deinit {
        dragPrimer?.cancel()
        if let monitor = dragMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

// After:
    deinit {
        dragPrimer?.cancel()
        if let monitor = dragMonitor {
            NSEvent.removeMonitor(monitor)
        }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        cancellables.removeAll()
    }
```

- [ ] **Step 2: B2 — CapsuleAppDelegate 添加 deinit**

Add after `applicationWillTerminate` method (after line 133):

```swift
    deinit {
        if let monitor = shortcutMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
```

- [ ] **Step 3: B3 — MenuBarService 保存并清理 monitor**

In `MenuBarService.swift`:

a) Add property after `private var menu: NSMenu?`:
```swift
    private var mouseMonitor: Any?
```

b) In `start()`, change the `NSEvent.addLocalMonitorForEvents(...)` call to save the result:
```swift
// Before:
            NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in

// After:
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
```

c) In `stop()`, remove the monitor:
```swift
// Before:
    func stop() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

// After:
    func stop() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }
```

- [ ] **Step 4: 构建并运行测试**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test 2>&1 | grep -E "(Test|PASS|FAIL|BUILD)"
```

Expected: all tests pass (including existing deinit tests).

- [ ] **Step 5: 提交**

```bash
git add "Mini Capsule/UI/CapsuleWindowController.swift" "Mini Capsule/Mini_CapsuleApp.swift" "Mini Capsule/Services/MenuBarService.swift"
git commit -m "fix: add missing deinit observer/monitor cleanup (B1, B2, B3)"
```

---

### Task 7: 创建 CapsuleViewModel (B5 修复)

**Files:**
- Create: `Mini Capsule/UI/CapsuleViewModel.swift`
- Modify: `Mini Capsule.xcodeproj` (add new file to target)

**Interfaces:**
- Consumes: `SettingsStore` (panelOpacityUnfocused, hoverExpandDelay, hoverCollapseDelay)
- Produces: `@MainActor @Observable final class CapsuleViewModel`
  - `var isExpanded: Bool`
  - `var isExpandingReady: Bool`
  - `var isCapturing: Bool`
  - `var isDragging: Bool`
  - `var windowOpacity: Double`
  - `func onHoverEnter()`, `func onHoverExit()`, `func collapse()`
  - `func onDragStart()`, `func onDragEnd()`
  - `func onNewItemCaptured()`

- [ ] **Step 1: 创建 CapsuleViewModel.swift**

```swift
// Mini Capsule/UI/CapsuleViewModel.swift
import SwiftUI
import Foundation

@MainActor
@Observable
final class CapsuleViewModel {
    // MARK: - Published State

    var isExpanded = false
    var isExpandingReady = false
    var isCapturing = false
    var isDragging = false

    // MARK: - Dependencies

    let settings: SettingsStore

    // MARK: - Internal

    private var hoverTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?

    // MARK: - Computed

    var windowOpacity: Double {
        if isExpanded { return 1.0 }
        let unfocused = settings.panelOpacityUnfocused
        return unfocused > 0 ? unfocused : 0.6
    }

    var expandDelay: Double {
        settings.hoverExpandDelay > 0 ? settings.hoverExpandDelay : 0.3
    }

    var collapseDelay: Double {
        settings.hoverCollapseDelay > 0 ? settings.hoverCollapseDelay : 1.0
    }

    // MARK: - Init

    init(settings: SettingsStore) {
        self.settings = settings
    }

    // MARK: - Hover State Machine

    func onHoverEnter() {
        hoverTask?.cancel()
        guard !isDragging else { return }
        isExpandingReady = false
        hoverTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.expandDelay))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                self.isExpanded = true
            }
            self.postExpandedNotification()
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self.isExpandingReady = true
        }
    }

    func onHoverExit() {
        hoverTask?.cancel()
        isExpandingReady = false
        hoverTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.collapseDelay))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                self.isExpanded = false
            }
            self.postExpandedNotification()
        }
    }

    func collapse() {
        hoverTask?.cancel()
        guard isExpanded else { return }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
            isExpanded = false
        }
        postExpandedNotification()
    }

    // MARK: - Drag State

    func onDragStart() {
        isDragging = true
        if isExpanded {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isExpanded = false
            }
            postExpandedNotification()
        }
    }

    func onDragEnd() {
        isDragging = false
    }

    // MARK: - Capture Animation

    func onNewItemCaptured() {
        isCapturing = true
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.isCapturing = false
        }
    }

    // MARK: - Private

    private func postExpandedNotification() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(
                name: .capsuleDidChangeExpanded,
                object: nil,
                userInfo: ["isExpanded": self.isExpanded]
            )
        }
    }
}
```

- [ ] **Step 2: 添加到 Xcode 项目**

```bash
ruby -e "
require 'xcodeproj'
project = Xcodeproj::Project.open('Mini Capsule.xcodeproj')
target = project.targets.find { |t| t.name == 'Mini Capsule' }
group = project.main_group.find_subpath('Mini Capsule/UI', true)
file_ref = group.new_file('CapsuleViewModel.swift')
target.source_build_phase.add_file_reference(file_ref)
project.save
puts 'Added CapsuleViewModel.swift to target'
"
```

- [ ] **Step 3: 构建验证**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED** (no consumers yet, but file compiles)

- [ ] **Step 4: 提交**

```bash
git add "Mini Capsule/UI/CapsuleViewModel.swift" "Mini Capsule.xcodeproj/project.pbxproj"
git commit -m "feat: add CapsuleViewModel with Task-based hover state machine (B5)"
```

---

### Task 8: 创建 ClipboardListViewModel

**Files:**
- Create: `Mini Capsule/UI/ClipboardListViewModel.swift`
- Modify: `Mini Capsule.xcodeproj` (add new file to target)

**Interfaces:**
- Consumes: `ModelContext`, `SettingsStore`
- Produces: `@MainActor @Observable final class ClipboardListViewModel`
  - Filter state: searchText, filterType (ContentFilter enum)
  - Selection state: selectedItemIDs, isMultiSelectMode, lastCopiedItemID
  - Actions: copyItem, pasteItem, deleteItem, deleteSelected, togglePin, editText, toggleMultiSelect
  - Keyboard: moveSelectionUp, moveSelectionDown, confirmSelection, handleEscape, selectAll
  - Computed: filteredItems, pinnedCount, totalCount

- [ ] **Step 1: 创建 ClipboardListViewModel.swift**

```swift
// Mini Capsule/UI/ClipboardListViewModel.swift
import SwiftUI
import SwiftData
import AppKit

enum ContentFilter: String, CaseIterable {
    case all = "全部"
    case text = "文本"
    case image = "图片"

    var systemImage: String {
        switch self {
        case .all: return "square.stack"
        case .text: return "doc.text"
        case .image: return "photo"
        }
    }
}

@MainActor
@Observable
final class ClipboardListViewModel {
    // MARK: - Filter State

    var searchText = ""
    var filterType: ContentFilter = .all

    // MARK: - Selection State

    var selectedItemIDs = Set<UUID>()
    var isMultiSelectMode = false
    var lastCopiedItemID: UUID?

    // MARK: - Dependencies

    let modelContext: ModelContext
    let settings: SettingsStore

    // MARK: - Init

    init(modelContext: ModelContext, settings: SettingsStore) {
        self.modelContext = modelContext
        self.settings = settings
    }

    // MARK: - Computed

    /// Fetch all items, sorted by pinned-first then timestamp descending.
    /// Pinned items sorted by sortOrder (ascending), unpinned by timestamp.
    var filteredItems: [ClipItem] {
        let descriptor = FetchDescriptor<ClipItem>(
            sortBy: [SortDescriptor(\ClipItem.timestamp, order: .reverse)]
        )
        let allItems = (try? modelContext.fetch(descriptor)) ?? []

        let typeFiltered: [ClipItem]
        switch filterType {
        case .all:
            typeFiltered = allItems
        case .text:
            typeFiltered = allItems.filter { $0.contentTypeRaw == "text" }
        case .image:
            typeFiltered = allItems.filter { $0.contentTypeRaw == "image" }
        }

        let searched: [ClipItem]
        if searchText.isEmpty {
            searched = typeFiltered
        } else {
            searched = typeFiltered.filter { item in
                item.textContent?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }

        // Pinned items first, sorted by sortOrder; unpinned by timestamp
        return searched.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            if a.isPinned {
                return (a.sortOrder ?? Int.max) < (b.sortOrder ?? Int.max)
            }
            return a.timestamp > b.timestamp
        }
    }

    var pinnedCount: Int {
        let descriptor = FetchDescriptor<ClipItem>(sortBy: [])
        let allItems = (try? modelContext.fetch(descriptor)) ?? []
        return allItems.filter(\.isPinned).count
    }

    // MARK: - Actions

    func copyItem(_ item: ClipItem) {
        PasteService.copyToClipboard(item)
        item.pasteCount += 1
        item.lastPastedAt = Date()
        item.timestamp = Date()
        try? modelContext.save()
        lastCopiedItemID = item.id
    }

    func pasteItem(_ item: ClipItem) {
        PasteService.paste(item, context: modelContext)
    }

    func deleteItem(_ item: ClipItem) {
        if let idx = selectedItemIDs.firstIndex(of: item.id) {
            selectedItemIDs.remove(at: idx)
        }
        modelContext.delete(item)
        try? modelContext.save()
    }

    func deleteSelected() {
        guard isMultiSelectMode, !selectedItemIDs.isEmpty else { return }
        let descriptor = FetchDescriptor<ClipItem>(sortBy: [])
        guard let items = try? modelContext.fetch(descriptor) else { return }
        for item in items where selectedItemIDs.contains(item.id) {
            modelContext.delete(item)
        }
        try? modelContext.save()
        selectedItemIDs.removeAll()
        isMultiSelectMode = false
    }

    func togglePin(_ item: ClipItem) {
        item.isPinned.toggle()
        if item.isPinned {
            // Assign next sort order
            let pinned = (try? modelContext.fetch(FetchDescriptor<ClipItem>(sortBy: [])))?.filter(\.isPinned) ?? []
            item.sortOrder = (pinned.map { $0.sortOrder ?? 0 }.max() ?? -1) + 1
        } else {
            item.sortOrder = nil
        }
        try? modelContext.save()
    }

    func editText(_ item: ClipItem, content: String) {
        item.textContent = content
        try? modelContext.save()
    }

    func toggleMultiSelect() {
        isMultiSelectMode.toggle()
        if !isMultiSelectMode {
            selectedItemIDs.removeAll()
        }
    }

    // MARK: - Keyboard Navigation

    func moveSelectionUp() {
        let items = filteredItems
        guard !items.isEmpty else { return }
        guard let currentID = selectedItemIDs.first,
              let idx = items.firstIndex(where: { $0.id == currentID }) else {
            selectedItemIDs = [items[0].id]
            return
        }
        let prev = max(idx - 1, 0)
        selectedItemIDs = [items[prev].id]
    }

    func moveSelectionDown() {
        let items = filteredItems
        guard !items.isEmpty else { return }
        guard let currentID = selectedItemIDs.first,
              let idx = items.firstIndex(where: { $0.id == currentID }) else {
            selectedItemIDs = [items[0].id]
            return
        }
        let next = min(idx + 1, items.count - 1)
        selectedItemIDs = [items[next].id]
    }

    func confirmSelection() {
        guard let selectedID = selectedItemIDs.first,
              let item = filteredItems.first(where: { $0.id == selectedID }) else { return }
        copyItem(item)
    }

    func handleEscape() {
        if !searchText.isEmpty {
            searchText = ""
        } else if isMultiSelectMode {
            toggleMultiSelect()
        }
        // collapse is handled by CapsuleViewModel — KeyboardEventHandler
        // calls this then CapsuleViewModel.collapse()
    }

    func selectAll() {
        selectedItemIDs = Set(filteredItems.map(\.id))
    }
}
```

- [ ] **Step 2: 添加到 Xcode 项目**

```bash
ruby -e "
require 'xcodeproj'
project = Xcodeproj::Project.open('Mini Capsule.xcodeproj')
target = project.targets.find { |t| t.name == 'Mini Capsule' }
group = project.main_group.find_subpath('Mini Capsule/UI', true)
file_ref = group.new_file('ClipboardListViewModel.swift')
target.source_build_phase.add_file_reference(file_ref)
project.save
puts 'Added ClipboardListViewModel.swift to target'
"
```

- [ ] **Step 3: 构建验证**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 4: 提交**

```bash
git add "Mini Capsule/UI/ClipboardListViewModel.swift" "Mini Capsule.xcodeproj/project.pbxproj"
git commit -m "feat: add ClipboardListViewModel with search, filter, multi-select, keyboard nav"
```

---

### Task 9: 重构 CapsuleView 使用 CapsuleViewModel

**Files:**
- Modify: `Mini Capsule/UI/CapsuleView.swift` — 完全重写

**Interfaces:**
- Consumes: `CapsuleViewModel`, `ClipboardListViewModel`, `SettingsStore` (via @Environment)
- Produces: clean CapsuleView using ViewModel state instead of @State

- [ ] **Step 1: 重写 CapsuleView.swift**

Complete replacement of current CapsuleView (120 lines):

```swift
// Mini Capsule/UI/CapsuleView.swift
import SwiftUI
import SwiftData

struct CapsuleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipItem.timestamp, order: .reverse) private var items: [ClipItem]

    @State private var capsuleVM: CapsuleViewModel
    @State private var listVM: ClipboardListViewModel
    @Environment(SettingsStore.self) private var settings

    init(modelContext: ModelContext, settings: SettingsStore) {
        let capsuleVM = CapsuleViewModel(settings: settings)
        let listVM = ClipboardListViewModel(modelContext: modelContext, settings: settings)
        _capsuleVM = State(initialValue: capsuleVM)
        _listVM = State(initialValue: listVM)
    }

    var body: some View {
        Group {
            if capsuleVM.isExpanded {
                CapsuleExpandedView(viewModel: listVM, capsuleViewModel: capsuleVM)
            } else {
                CapsuleCollapsedView(
                    latestItem: items.first,
                    isCapturing: capsuleVM.isCapturing,
                    collapsedStyle: settings.collapsedStyle
                )
            }
        }
        .opacity(capsuleVM.windowOpacity)
        .animation(.easeInOut(duration: 0.3), value: capsuleVM.windowOpacity)
        .onHover { hovering in
            if hovering {
                capsuleVM.onHoverEnter()
            } else {
                capsuleVM.onHoverExit()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .capsuleDragStarted)) { _ in
            capsuleVM.onDragStart()
        }
        .onReceive(NotificationCenter.default.publisher(for: .capsuleDragEnded)) { _ in
            capsuleVM.onDragEnd()
        }
        .onChange(of: items.first?.id) { _, _ in
            capsuleVM.onNewItemCaptured()
        }
    }
}
```

- [ ] **Step 2: 更新 CapsuleWindowController 中的 CapsuleView 初始化**

In `CapsuleWindowController.swift`, the current init creates CapsuleView like:

```swift
let capsuleView = CapsuleView()
    .environmentObject(settingsStore)
    .modelContainer(modelContainer)
```

Change to:

```swift
let capsuleView = CapsuleView(
    modelContext: modelContainer.mainContext,
    settings: settingsStore
)
.modelContainer(modelContainer)
.environment(settingsStore)
```

Note: `.environmentObject(settingsStore)` → `.environment(settingsStore)` for @Observable compatibility.

- [ ] **Step 3: 构建验证**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -10
```

Expected: **BUILD SUCCEEDED** (may have warnings about CapsuleExpandedView signature change — will be fixed in Task 11)

- [ ] **Step 4: 提交**

```bash
git add "Mini Capsule/UI/CapsuleView.swift" "Mini Capsule/UI/CapsuleWindowController.swift"
git commit -m "refactor: CapsuleView uses CapsuleViewModel + ClipboardListViewModel"
```

---

### Task 10: 提取 KeyboardEventHandler

**Files:**
- Create: `Mini Capsule/UI/KeyboardEventHandler.swift`
- Modify: `Mini Capsule/UI/CapsuleExpandedView.swift` — 删除 KeyboardMonitorView 定义
- Modify: `Mini Capsule.xcodeproj` (add new file to target)

**Interfaces:**
- Consumes: `ClipboardListViewModel` (via Coordinator弱引用)
- Produces: `KeyboardEventHandler` NSViewRepresentable 独立组件

- [ ] **Step 1: 创建 KeyboardEventHandler.swift**

```swift
// Mini Capsule/UI/KeyboardEventHandler.swift
import SwiftUI

/// Independent NSViewRepresentable that bridges NSEvent keyDown to
/// ClipboardListViewModel keyboard navigation methods.
/// Replaces the fileprivate KeyboardMonitorView previously embedded
/// in CapsuleExpandedView.swift.
struct KeyboardEventHandler: NSViewRepresentable {
    let viewModel: ClipboardListViewModel

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            return context.coordinator.handleKeyEvent(event) ? nil : event
        }
        context.coordinator.owner = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // ViewModel is observed via @Observable — no manual update needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    final class Coordinator {
        private weak var viewModel: ClipboardListViewModel?
        weak var owner: MonitorView?

        init(viewModel: ClipboardListViewModel) {
            self.viewModel = viewModel
        }

        func handleKeyEvent(_ event: NSEvent) -> Bool {
            guard let vm = viewModel, !vm.filteredItems.isEmpty else { return false }

            // Check for Cmd+A first (select all)
            if event.modifierFlags.contains(.command) && event.keyCode == 0 {
                vm.selectAll()
                return true
            }

            switch event.keyCode {
            case 125: // ↓
                vm.moveSelectionDown()
                return true
            case 126: // ↑
                vm.moveSelectionUp()
                return true
            case 36, 76: // Return, numpad Enter
                vm.confirmSelection()
                return true
            case 53: // Escape
                vm.handleEscape()
                // Also signal CapsuleViewModel to collapse if needed
                NotificationCenter.default.post(
                    name: .capsuleEscapePressed,
                    object: nil
                )
                return true
            default:
                return false // pass through to search field
            }
        }
    }

    final class MonitorView: NSView {
        var monitor: Any?

        deinit {
            if let m = monitor {
                NSEvent.removeMonitor(m)
            }
        }
    }
}
```

- [ ] **Step 2: 添加 capsuleEscapePressed 通知名**

在 `NotificationNames.swift` 的 Capsule Notifications 扩展中添加：

```swift
/// Posted when Escape key is pressed in the expanded capsule.
static let capsuleEscapePressed = Notification.Name("capsuleEscapePressed")
```

- [ ] **Step 3: 从 CapsuleExpandedView 中删除 KeyboardMonitorView**

Remove the entire `// MARK: - Keyboard Monitor (NSViewRepresentable)` section (lines 143-223 in current file) and remove `.background(KeyboardMonitorView(...))` from the view body.

Will be completed in Task 11 when we refactor CapsuleExpandedView.

- [ ] **Step 4: 添加到 Xcode 项目**

```bash
ruby -e "
require 'xcodeproj'
project = Xcodeproj::Project.open('Mini Capsule.xcodeproj')
target = project.targets.find { |t| t.name == 'Mini Capsule' }
group = project.main_group.find_subpath('Mini Capsule/UI', true)
file_ref = group.new_file('KeyboardEventHandler.swift')
target.source_build_phase.add_file_reference(file_ref)
project.save
puts 'Added KeyboardEventHandler.swift to target'
"
```

- [ ] **Step 5: 构建验证**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 6: 提交**

```bash
git add "Mini Capsule/UI/KeyboardEventHandler.swift" "Mini Capsule/Settings/NotificationNames.swift" "Mini Capsule.xcodeproj/project.pbxproj"
git commit -m "feat: extract KeyboardEventHandler as independent NSViewRepresentable"
```

---

### Task 11: 重构 CapsuleExpandedView (U1, U4, U5)

**Files:**
- Modify: `Mini Capsule/UI/CapsuleExpandedView.swift` — 完全重写

**Interfaces:**
- Consumes: `ClipboardListViewModel`, `CapsuleViewModel` (for Escape collapse)
- Produces: clean ExpandedView with filter tabs, multi-select, KeyboardEventHandler

- [ ] **Step 1: 重写 CapsuleExpandedView.swift**

Complete replacement:

```swift
// Mini Capsule/UI/CapsuleExpandedView.swift
import SwiftUI
import SwiftData
import AppKit

struct CapsuleExpandedView: View {
    @Bindable var viewModel: ClipboardListViewModel
    var capsuleViewModel: CapsuleViewModel

    @FocusState private var isSearchFocused: Bool
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar

            Divider()

            // Filter tabs
            filterTabs

            Divider()

            // Item list
            itemList

            Divider()

            // Bottom bar
            bottomBar
        }
        .frame(width: 280, height: 360)
        .background {
            backgroundLayer
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        .onAppear {
            isSearchFocused = true
            viewModel.selectedItemIDs = [viewModel.filteredItems.first?.id].compactMap { $0 }.map { Set([$0]) } ?? []
        }
        .onDisappear {
            viewModel.selectedItemIDs.removeAll()
            viewModel.isMultiSelectMode = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .capsuleEscapePressed)) { _ in
            // If search is empty and not in multi-select mode, collapse
            if viewModel.searchText.isEmpty && !viewModel.isMultiSelectMode {
                capsuleViewModel.collapse()
            }
        }
        .background(
            KeyboardEventHandler(viewModel: viewModel)
        )
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            TextField("搜索...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFocused)

            if #available(macOS 14.0, *) {
                SettingsLink {
                    Image(systemName: "gear")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }) {
                    Image(systemName: "gear")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Filter Tabs (U4)

    private var filterTabs: some View {
        HStack(spacing: 8) {
            ForEach(ContentFilter.allCases, id: \.rawValue) { filter in
                filterTab(filter)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func filterTab(_ filter: ContentFilter) -> some View {
        Button(action: { viewModel.filterType = filter }) {
            HStack(spacing: 4) {
                Image(systemName: filter.systemImage)
                    .font(.system(size: 10))
                Text(filter.rawValue)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                viewModel.filterType == filter
                    ? Color.accentColor.opacity(0.2)
                    : Color.clear
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Item List

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filteredItems) { item in
                    ClipItemRow(
                        item: item,
                        isSelected: viewModel.selectedItemIDs.contains(item.id),
                        isInteractive: capsuleViewModel.isExpandingReady,
                        isMultiSelectMode: viewModel.isMultiSelectMode,
                        onTap: {
                            if viewModel.isMultiSelectMode {
                                if viewModel.selectedItemIDs.contains(item.id) {
                                    viewModel.selectedItemIDs.remove(item.id)
                                } else {
                                    viewModel.selectedItemIDs.insert(item.id)
                                }
                            } else {
                                viewModel.copyItem(item)
                            }
                        },
                        onDelete: { viewModel.deleteItem(item) }
                    )

                    Divider()
                        .padding(.leading, 12)
                }
            }
        }
    }

    // MARK: - Bottom Bar (U5 batch delete)

    private var bottomBar: some View {
        HStack {
            if viewModel.isMultiSelectMode {
                Button(action: { viewModel.deleteSelected() }) {
                    Text("删除所选 (\(viewModel.selectedItemIDs.count))")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.selectedItemIDs.isEmpty)

                Spacer()

                Button("取消") {
                    viewModel.toggleMultiSelect()
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
            } else {
                if viewModel.pinnedCount > 0 {
                    Text("📌 已置顶 \(viewModel.pinnedCount) 条")
                        .font(.system(size: 11))
                }
                Spacer()
                Text("共 \(viewModel.filteredItems.count) 条")
                    .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundColor(.secondary)
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            if !settings.backgroundImageData.isEmpty,
               let nsImage = NSImage(data: settings.backgroundImageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            Rectangle()
                .fill(.ultraThinMaterial)
        }
    }
}
```

- [ ] **Step 2: 更新 ClipItemRow 签名**

`ClipItemRow` must accept the new `isMultiSelectMode` parameter. We'll update it in the call site above and the ClipItemRow definition in Task 14.

For now, temporarily add `isMultiSelectMode: Bool = false` parameter to the existing ClipItemRow. (Will be properly implemented in Task 14.)

- [ ] **Step 3: 构建验证**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -10
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 4: 提交**

```bash
git add "Mini Capsule/UI/CapsuleExpandedView.swift" "Mini Capsule/UI/ClipItemRow.swift"
git commit -m "feat: refactor CapsuleExpandedView with filter tabs, multi-select, keyboard nav (U1, U4, U5)"
```

---

### Task 12: 重构 CapsuleWindowController (B4 frame persistence)

**Files:**
- Modify: `Mini Capsule/UI/CapsuleWindowController.swift` — 重构 saveFrame/loadFrame, 清理

**Interfaces:**
- Consumes: `SettingsStore.capsuleWindowFrame` (Data?)
- Produces: Frame 持久化通过 SettingsStore

- [ ] **Step 1: 重写 saveFrame() 和 loadFrame()**

In `CapsuleWindowController.swift`:

Replace `saveFrame()` (lines 265-273):

```swift
// Before:
    private func saveFrame() {
        guard let frame = window?.frame else { return }
        let frameDict: [String: CGFloat] = [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "w": frame.size.width,
            "h": frame.size.height
        ]
        UserDefaults.standard.set(frameDict, forKey: SettingsKey.capsuleWindowFrameKey)
    }

// After:
    private func saveFrame() {
        guard let frame = window?.frame else { return }
        let frameDict: [String: CGFloat] = [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "w": frame.size.width,
            "h": frame.size.height
        ]
        if let data = try? JSONEncoder().encode(frameDict) {
            settingsStore.capsuleWindowFrame = data
        }
    }
```

Replace `loadFrame(style:)` (lines 276-299):

```swift
// Before:
    private static func loadFrame(style: String) -> NSRect {
        let size = style == "dot" ? dotCollapsedSize : capsuleCollapsedSize
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: size.width, height: size.height)
        }
        let screenWidth = screen.visibleFrame.width
        let screenHeight = screen.visibleFrame.maxY
        var x = (screenWidth - size.width) / 2
        var y = screenHeight - size.height - 40
        // Restore saved position
        if let dict = UserDefaults.standard.dictionary(forKey: SettingsKey.capsuleWindowFrameKey) as? [String: CGFloat],
           let savedX = dict["x"], let savedY = dict["y"] {
            ...
        }
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

// After:
    private func loadFrame(style: String) -> NSRect {
        let size = style == "dot" ? Self.dotCollapsedSize : Self.capsuleCollapsedSize
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: size.width, height: size.height)
        }
        let screenWidth = screen.visibleFrame.width
        let screenHeight = screen.visibleFrame.maxY
        var x = (screenWidth - size.width) / 2
        var y = screenHeight - size.height - 40
        // Restore saved position from SettingsStore
        if let data = settingsStore.capsuleWindowFrame,
           data.count > 0,
           let dict = try? JSONDecoder().decode([String: CGFloat].self, from: data),
           let savedX = dict["x"], let savedY = dict["y"] {
            let screenFrame = screen.visibleFrame
            let clampedX = min(max(savedX, screenFrame.minX), screenFrame.maxX - size.width)
            let clampedY = min(max(savedY, screenFrame.minY), screenFrame.maxY - size.height)
            x = clampedX
            y = clampedY
        }
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
```

Note: `loadFrame` changes from `static` to instance method since it now needs `settingsStore`.

Update the call in `init` from `Self.loadFrame(style:)` to `loadFrame(style:)`.

- [ ] **Step 2: 更新重置位置代码**

In the reset position observer (around line 238), replace:

```swift
UserDefaults.standard.removeObject(forKey: SettingsKey.capsuleWindowFrameKey)
```

with:

```swift
self.settingsStore.capsuleWindowFrame = Data()
```

- [ ] **Step 3: 清理旧的 UserDefaults 引用**

The init now takes `settingsStore` as parameter (already the case), confirm all `UserDefaults.standard` calls for `capsuleWindowFrameKey` are gone:

```bash
grep -n "capsuleWindowFrame" "Mini Capsule/UI/CapsuleWindowController.swift"
```

Should show only references to `settingsStore.capsuleWindowFrame`, not `UserDefaults.standard`.

- [ ] **Step 4: 构建并运行测试**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test 2>&1 | grep -E "(Test|PASS|FAIL|BUILD)"
```

Expected: existing CapsuleWindowController tests pass (they use notification-based testing, not direct UserDefaults access).

- [ ] **Step 5: 提交**

```bash
git add "Mini Capsule/UI/CapsuleWindowController.swift"
git commit -m "refactor: CapsuleWindowController frame persistence via SettingsStore (B4)"
```

---

### Task 13: 添加 CopyFeedbackView (U3)

**Files:**
- Create: `Mini Capsule/UI/CopyFeedbackView.swift`
- Modify: `Mini Capsule/UI/CapsuleExpandedView.swift` — 叠放 CopyFeedbackView
- Modify: `Mini Capsule.xcodeproj` (add new file to target)

- [ ] **Step 1: 创建 CopyFeedbackView.swift**

```swift
// Mini Capsule/UI/CopyFeedbackView.swift
import SwiftUI

struct CopyFeedbackView: View {
    let viewModel: ClipboardListViewModel
    @State private var isVisible = false
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
            Text("已复制")
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        .offset(y: isVisible ? 0 : 20)
        .opacity(isVisible ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isVisible)
        .onChange(of: viewModel.lastCopiedItemID) { _, newValue in
            guard newValue != nil else { return }
            show()
        }
    }

    private func show() {
        feedbackTask?.cancel()
        isVisible = true
        feedbackTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            isVisible = false
        }
    }
}
```

- [ ] **Step 2: 在 CapsuleExpandedView 中集成**

In `CapsuleExpandedView.swift`, wrap the main VStack in a ZStack overlay:

```swift
// The main .frame(width: 280, height: 360) container becomes:
ZStack {
    // ... existing VStack content ...
    VStack { ... }
    .frame(width: 280, height: 360)
    .background { backgroundLayer }
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .shadow(...)

    // Copy feedback overlay
    VStack {
        Spacer()
        CopyFeedbackView(viewModel: viewModel)
            .padding(.bottom, 8)
    }
}
```

- [ ] **Step 3: 添加到 Xcode 项目**

```bash
ruby -e "
require 'xcodeproj'
project = Xcodeproj::Project.open('Mini Capsule.xcodeproj')
target = project.targets.find { |t| t.name == 'Mini Capsule' }
group = project.main_group.find_subpath('Mini Capsule/UI', true)
file_ref = group.new_file('CopyFeedbackView.swift')
target.source_build_phase.add_file_reference(file_ref)
project.save
puts 'Added CopyFeedbackView.swift to target'
"
```

- [ ] **Step 4: 构建验证**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 5: 提交**

```bash
git add "Mini Capsule/UI/CopyFeedbackView.swift" "Mini Capsule/UI/CapsuleExpandedView.swift" "Mini Capsule.xcodeproj/project.pbxproj"
git commit -m "feat: add CopyFeedbackView HUD on copy (U3)"
```

---

### Task 14: 增强 ClipItemRow — 右键菜单 + 多选 + PopoverEditor (E4, E5, U2)

**Files:**
- Create: `Mini Capsule/UI/PopoverEditorView.swift`
- Modify: `Mini Capsule/UI/ClipItemRow.swift` — 完全重写
- Modify: `Mini Capsule.xcodeproj` (add new files to target)

- [ ] **Step 1: 创建 PopoverEditorView.swift**

```swift
// Mini Capsule/UI/PopoverEditorView.swift
import SwiftUI

struct PopoverEditorView: View {
    let item: ClipItem
    let onSave: (String) -> Void

    @State private var editedText: String
    @Environment(\.dismiss) private var dismiss

    init(item: ClipItem, onSave: @escaping (String) -> Void) {
        self.item = item
        self.onSave = onSave
        _editedText = State(initialValue: item.textContent ?? "")
    }

    var body: some View {
        VStack(spacing: 12) {
            TextEditor(text: $editedText)
                .font(.system(size: 12, design: .monospaced))
                .frame(minWidth: 250, minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 12) {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))

                Spacer()

                Button("保存") {
                    onSave(editedText)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .font(.system(size: 12))
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}
```

- [ ] **Step 2: 重写 ClipItemRow.swift**

Complete replacement with debounced hover, context menu, multi-select UI:

```swift
// Mini Capsule/UI/ClipItemRow.swift
import SwiftUI

struct ClipItemRow: View {
    let item: ClipItem
    let isSelected: Bool
    let isInteractive: Bool
    var isMultiSelectMode: Bool = false
    var onTap: () -> Void
    var onDelete: () -> Void

    @State private var isHovering = false
    @State private var showPopover = false
    @State private var showEditor = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 10) {
            // Multi-select checkbox
            if isMultiSelectMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.system(size: 16))
            }

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

            if isHovering && isInteractive && !isMultiSelectMode {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(selectionBackground)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoverTask?.cancel()
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(200))  // U2: debounce
                    guard !Task.isCancelled else { return }
                    isHovering = true
                    showPopover = true
                }
            } else {
                hoverTask?.cancel()
                isHovering = false
                showPopover = false
                showEditor = false
            }
        }
        .onTapGesture {
            guard isInteractive else { return }
            onTap()
        }
        .contextMenu { contextMenuContent }  // E5
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            popoverContent
        }
        .popover(isPresented: $showEditor, arrowEdge: .trailing) {
            PopoverEditorView(item: item) { newContent in
                // onSave is handled via the parent view model
                // We post a notification for the view model to pick up
                NotificationCenter.default.post(
                    name: .editTextItem,
                    object: nil,
                    userInfo: ["itemID": item.id, "content": newContent]
                )
            }
        }
    }

    // MARK: - Context Menu (E5)

    @ViewBuilder
    private var contextMenuContent: some View {
        Button("复制") { onTap() }
            .keyboardShortcut("c", modifiers: [])

        if item.contentTypeRaw == "text" {
            Button("粘贴到前台") {
                NotificationCenter.default.post(
                    name: .pasteItemToFront,
                    object: nil,
                    userInfo: ["itemID": item.id]
                )
            }
        }

        Divider()

        Button(item.isPinned ? "取消置顶" : "置顶") {
            NotificationCenter.default.post(
                name: .togglePinItem,
                object: nil,
                userInfo: ["itemID": item.id]
            )
        }

        if item.contentTypeRaw == "text" {
            Button("编辑") {
                showEditor = true
            }
        }

        Divider()

        Button("删除", role: .destructive) {
            onDelete()
        }
    }

    // MARK: - Popover Content

    @ViewBuilder
    private var popoverContent: some View {
        if item.contentTypeRaw == "image",
           let imageData = item.imageData,
           let nsImage = NSImage(data: imageData) {
            imagePreview(nsImage)
                .padding(8)
        } else if item.contentTypeRaw == "text",
                  let text = item.textContent {
            VStack(spacing: 0) {
                textPreview(text)
                    .padding(8)
                Divider()
                Button("编辑") {           // E4: Edit button in popover
                    showEditor = true
                    showPopover = false
                }
                .font(.system(size: 11))
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Selection

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.15))
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Previews (unchanged from original)

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

    @ViewBuilder
    private func textPreview(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 300, maxHeight: 200)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    // MARK: - Type Icon

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
        case "text": return Image(systemName: "doc.text")
        case "file": return Image(systemName: "doc")
        default: return Image(systemName: "questionmark")
        }
    }

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

- [ ] **Step 3: 添加新通知名**

In `NotificationNames.swift`, add:

```swift
/// Posted to request editing a text item. UserInfo: ["itemID": UUID, "content": String]
static let editTextItem = Notification.Name("editTextItem")

/// Posted to request pasting an item to frontmost app. UserInfo: ["itemID": UUID]
static let pasteItemToFront = Notification.Name("pasteItemToFront")

/// Posted to toggle pin status of an item. UserInfo: ["itemID": UUID]
static let togglePinItem = Notification.Name("togglePinItem")
```

- [ ] **Step 4: 在 CapsuleExpandedView 中监听通知**

In `CapsuleExpandedView.swift`, add `onReceive` observers for the new notification names. Each maps to the appropriate ViewModel action:

```swift
.onReceive(NotificationCenter.default.publisher(for: .editTextItem)) { notification in
    guard let itemID = notification.userInfo?["itemID"] as? UUID,
          let content = notification.userInfo?["content"] as? String,
          let item = viewModel.filteredItems.first(where: { $0.id == itemID }) else { return }
    viewModel.editText(item, content: content)
}
.onReceive(NotificationCenter.default.publisher(for: .pasteItemToFront)) { notification in
    guard let itemID = notification.userInfo?["itemID"] as? UUID,
          let item = viewModel.filteredItems.first(where: { $0.id == itemID }) else { return }
    viewModel.pasteItem(item)
}
.onReceive(NotificationCenter.default.publisher(for: .togglePinItem)) { notification in
    guard let itemID = notification.userInfo?["itemID"] as? UUID,
          let item = viewModel.filteredItems.first(where: { $0.id == itemID }) else { return }
    viewModel.togglePin(item)
}
```

- [ ] **Step 5: 添加到 Xcode 项目**

```bash
ruby -e "
require 'xcodeproj'
project = Xcodeproj::Project.open('Mini Capsule.xcodeproj')
target = project.targets.find { |t| t.name == 'Mini Capsule' }
group = project.main_group.find_subpath('Mini Capsule/UI', true)
file_ref = group.new_file('PopoverEditorView.swift')
target.source_build_phase.add_file_reference(file_ref)
project.save
puts 'Added PopoverEditorView.swift to target'
"
```

- [ ] **Step 6: 构建验证**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -10
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 7: 提交**

```bash
git add "Mini Capsule/UI/ClipItemRow.swift" "Mini Capsule/UI/PopoverEditorView.swift" "Mini Capsule/UI/CapsuleExpandedView.swift" "Mini Capsule/Settings/NotificationNames.swift" "Mini Capsule.xcodeproj/project.pbxproj"
git commit -m "feat: add context menu, popover editor, debounced hover, multi-select UI (E4, E5, U2)"
```

---

### Task 15: CapsuleCollapsedView — 新增 Icon 样式 (E2)

**Files:**
- Modify: `Mini Capsule/UI/CapsuleCollapsedView.swift`

- [ ] **Step 1: 添加 icon 样式分支**

In `CapsuleCollapsedView.swift`, update the body:

```swift
// Before:
    var body: some View {
        if collapsedStyle == "dot" {
            dotView
        } else {
            capsuleView
        }
    }

// After:
    var body: some View {
        switch collapsedStyle {
        case "dot":
            dotView
        case "icon":
            iconView
        default:
            capsuleView
        }
    }
```

- [ ] **Step 2: 添加 iconView 实现**

Add after `dotView`:

```swift
    // MARK: - Icon variant (E2)

    private var iconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.ultraThinMaterial)
                .frame(width: 24, height: 24)

            Image(systemName: typeIconName)
                .font(.system(size: 14))
                .foregroundColor(.primary)
        }
        .scaleEffect(isCapturing ? 1.2 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isCapturing)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private var typeIconName: String {
        guard let item = latestItem else { return "clipboard" }
        switch item.contentTypeRaw {
        case "text": return "doc.text"
        case "image": return "photo"
        case "file": return "doc"
        default: return "clipboard"
        }
    }
```

- [ ] **Step 3: 更新 CapsuleWindowController icon 样式对应的尺寸**

In `CapsuleWindowController.swift`, add icon size constant:

```swift
private static let iconCollapsedSize = NSSize(width: 24, height: 24)
```

Update `currentCollapsedSize`:

```swift
private var currentCollapsedSize: NSSize {
    switch settingsStore.collapsedStyle {
    case "dot": return Self.dotCollapsedSize
    case "icon": return Self.iconCollapsedSize
    default: return Self.capsuleCollapsedSize
    }
}
```

Update `loadFrame(style:)` similarly to handle `"icon"` style.

Update corner radius for icon style (in the observeExpandedState and objectWillChange sink):

```swift
// For collapsed state:
let cornerRadius: CGFloat
switch settingsStore.collapsedStyle {
case "dot": cornerRadius = 6
case "icon": cornerRadius = 6
default: cornerRadius = 18
}
```

- [ ] **Step 4: 构建验证**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 5: 提交**

```bash
git add "Mini Capsule/UI/CapsuleCollapsedView.swift" "Mini Capsule/UI/CapsuleWindowController.swift"
git commit -m "feat: add icon collapsed style (E2)"
```

---

### Task 16: 动画优化 (E3) + 最终集成

**Files:**
- Modify: `Mini Capsule/UI/CapsuleViewModel.swift` — 动画参数已在创建时设置
- Modify: `Mini Capsule/UI/CapsuleCollapsedView.swift` — 捕获动画 bounce

- [ ] **Step 1: 优化 CapsuleCollapsedView 捕获动画**

In `CapsuleCollapsedView.swift`, update the capture animation:
- dot: `.spring(response: 0.3, dampingFraction: 0.6)` (already set in iconView)
- capsule indicator circle: same spring

In `dotView`, change:

```swift
.animation(.easeInOut(duration: 0.3), value: isCapturing)
```

to:

```swift
.animation(.spring(response: 0.3, dampingFraction: 0.6), value: isCapturing)
```

In `capsuleView`'s indicator Circle, change the same animation.

- [ ] **Step 2: 确认 CapsuleViewModel 动画参数**

The animation curves in CapsuleViewModel were set during Task 7:
- Expand: `.spring(response: 0.35, dampingFraction: 0.75)` with implicit scale
- Collapse: `.spring(response: 0.2, dampingFraction: 0.7)`
- CopyFeedback: `.spring(response: 0.3, dampingFraction: 0.7)` (in CopyFeedbackView)

No additional changes needed — parameters were set correctly during creation.

- [ ] **Step 3: 完整构建 + 测试**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test 2>&1 | grep -E "(Test|PASS|FAIL|BUILD)"
```

Expected: all tests pass, BUILD SUCCEEDED.

- [ ] **Step 4: 提交**

```bash
git add "Mini Capsule/UI/CapsuleCollapsedView.swift"
git commit -m "feat: polish animations with spring curves and bounce (E3)"
```

---

### Task 17: CapsuleViewModelTests

**Files:**
- Create: `Mini CapsuleTests/CapsuleViewModelTests.swift`
- Modify: `Mini Capsule.xcodeproj` (add to test target)

**Test coverage:** Tests 1-9, 45 from spec

- [ ] **Step 1: 创建 CapsuleViewModelTests.swift**

```swift
// Mini CapsuleTests/CapsuleViewModelTests.swift
import Testing
import Foundation
@testable import Mini_Capsule

@MainActor
struct CapsuleViewModelTests {

    @Test func initialStateAllDefaults() async throws {
        let settings = SettingsStore()
        let vm = CapsuleViewModel(settings: settings)

        #expect(vm.isExpanded == false)
        #expect(vm.isExpandingReady == false)
        #expect(vm.isCapturing == false)
        #expect(vm.isDragging == false)
        #expect(vm.windowOpacity == settings.panelOpacityUnfocused)

        settings.resetAll()
    }

    @Test func onHoverEnterSetsExpandedAfterDelay() async throws {
        let settings = SettingsStore()
        settings.hoverExpandDelay = 0.1
        let vm = CapsuleViewModel(settings: settings)

        vm.onHoverEnter()
        #expect(vm.isExpanded == false) // not yet

        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.isExpanded == true)

        settings.resetAll()
    }

    @Test func onHoverEnterThenQuickExitDoesNotExpand() async throws {
        let settings = SettingsStore()
        settings.hoverExpandDelay = 0.5
        let vm = CapsuleViewModel(settings: settings)

        vm.onHoverEnter()
        try await Task.sleep(for: .milliseconds(50))
        vm.onHoverExit()

        try await Task.sleep(for: .milliseconds(600))
        #expect(vm.isExpanded == false)

        settings.resetAll()
    }

    @Test func onHoverExitCollapsesAfterDelay() async throws {
        let settings = SettingsStore()
        settings.hoverExpandDelay = 0.05
        settings.hoverCollapseDelay = 0.1
        let vm = CapsuleViewModel(settings: settings)

        vm.onHoverEnter()
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.isExpanded == true)

        vm.onHoverExit()
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.isExpanded == false)

        settings.resetAll()
    }

    @Test func collapseImmediatelyCollapses() async throws {
        let settings = SettingsStore()
        settings.hoverExpandDelay = 0.05
        let vm = CapsuleViewModel(settings: settings)

        vm.onHoverEnter()
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.isExpanded == true)

        vm.collapse()
        #expect(vm.isExpanded == false)

        settings.resetAll()
    }

    @Test func onDragStartDisablesHover() async throws {
        let settings = SettingsStore()
        settings.hoverExpandDelay = 0.1
        let vm = CapsuleViewModel(settings: settings)

        vm.onDragStart()
        #expect(vm.isDragging == true)

        vm.onHoverEnter()
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.isExpanded == false) // hover blocked by drag

        settings.resetAll()
    }

    @Test func onDragEndReenablesHover() async throws {
        let settings = SettingsStore()
        settings.hoverExpandDelay = 0.1
        let vm = CapsuleViewModel(settings: settings)

        vm.onDragStart()
        vm.onDragEnd()
        #expect(vm.isDragging == false)

        vm.onHoverEnter()
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.isExpanded == true)

        settings.resetAll()
    }

    @Test func onNewItemCapturedTriggersAnimation() async throws {
        let settings = SettingsStore()
        let vm = CapsuleViewModel(settings: settings)

        vm.onNewItemCaptured()
        #expect(vm.isCapturing == true)

        try await Task.sleep(for: .seconds(2.1))
        #expect(vm.isCapturing == false)

        settings.resetAll()
    }

    @Test func windowOpacityExpandedIsOne() async throws {
        let settings = SettingsStore()
        settings.panelOpacityUnfocused = 0.5
        let vm = CapsuleViewModel(settings: settings)

        #expect(vm.windowOpacity == 0.5)

        vm.onHoverEnter()
        settings.hoverExpandDelay = 0.05
        vm.onHoverEnter()
        try await Task.sleep(for: .milliseconds(150))

        #expect(vm.windowOpacity == 1.0)

        settings.resetAll()
    }

    @Test func rapidHoverInOutInResolvesCorrectly() async throws {  // B5 fix verification
        let settings = SettingsStore()
        settings.hoverExpandDelay = 0.2
        settings.hoverCollapseDelay = 0.3
        let vm = CapsuleViewModel(settings: settings)

        vm.onHoverEnter()
        try await Task.sleep(for: .milliseconds(50))
        vm.onHoverExit()
        try await Task.sleep(for: .milliseconds(50))
        vm.onHoverEnter() // re-enter before collapse fires

        try await Task.sleep(for: .milliseconds(300))
        // Should be expanded (not collapsed, not race-conditioned)
        #expect(vm.isExpanded == true)

        settings.resetAll()
    }
}
```

- [ ] **Step 2: 添加到 Xcode 测试 target**

```bash
ruby -e "
require 'xcodeproj'
project = Xcodeproj::Project.open('Mini Capsule.xcodeproj')
target = project.targets.find { |t| t.name == 'Mini CapsuleTests' }
group = project.main_group.find_subpath('Mini CapsuleTests', true)
file_ref = group.new_file('CapsuleViewModelTests.swift')
target.source_build_phase.add_file_reference(file_ref)
project.save
puts 'Added CapsuleViewModelTests.swift to test target'
"
```

- [ ] **Step 3: 运行测试**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:Mini_CapsuleTests/CapsuleViewModelTests test 2>&1 | grep -E "(Test|PASS|FAIL|✓|✗)"
```

Expected: all tests pass.

- [ ] **Step 4: 提交**

```bash
git add "Mini CapsuleTests/CapsuleViewModelTests.swift" "Mini Capsule.xcodeproj/project.pbxproj"
git commit -m "test: add CapsuleViewModelTests covering hover state machine, drag, capture, B5 fix"
```

---

### Task 18: ClipboardListViewModelTests

**Files:**
- Create: `Mini CapsuleTests/ClipboardListViewModelTests.swift`
- Modify: `Mini Capsule.xcodeproj` (add to test target)

**Test coverage:** Tests 10-23 from spec

- [ ] **Step 1: 创建 ClipboardListViewModelTests.swift**

```swift
// Mini CapsuleTests/ClipboardListViewModelTests.swift
import Testing
import Foundation
import SwiftData
@testable import Mini_Capsule

@MainActor
struct ClipboardListViewModelTests {

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func seedItems(context: ModelContext) {
        context.insert(ClipItem(timestamp: Date(), contentTypeRaw: "text", textContent: "Hello World", sourceAppBundleID: "com.test"))
        context.insert(ClipItem(timestamp: Date().addingTimeInterval(-10), contentTypeRaw: "text", textContent: "Goodbye", sourceAppBundleID: "com.test"))
        context.insert(ClipItem(timestamp: Date().addingTimeInterval(-20), contentTypeRaw: "image", imageData: Data([0x01, 0x02]), imageFileName: "test.png", imageMD5: "abc", sourceAppBundleID: "com.test"))
        try? context.save()
    }

    @Test func emptySearchReturnsAllItems() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        #expect(vm.filteredItems.count == 3)

        settings.resetAll()
    }

    @Test func searchFiltersByText() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        vm.searchText = "Hello"
        #expect(vm.filteredItems.count == 1)
        #expect(vm.filteredItems.first?.textContent == "Hello World")

        settings.resetAll()
    }

    @Test func searchNoMatchReturnsEmpty() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        vm.searchText = "zzzzzzz"
        #expect(vm.filteredItems.isEmpty)

        settings.resetAll()
    }

    @Test func filterTypeAllShowsAll() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        vm.filterType = .all
        #expect(vm.filteredItems.count == 3)

        settings.resetAll()
    }

    @Test func filterTypeTextShowsOnlyText() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        vm.filterType = .text
        #expect(vm.filteredItems.count == 2)
        #expect(vm.filteredItems.allSatisfy { $0.contentTypeRaw == "text" })

        settings.resetAll()
    }

    @Test func filterTypeImageShowsOnlyImages() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        vm.filterType = .image
        #expect(vm.filteredItems.count == 1)
        #expect(vm.filteredItems.first?.contentTypeRaw == "image")

        settings.resetAll()
    }

    @Test func singleSelectTogglesSelection() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        let item = vm.filteredItems.first!
        vm.selectedItemIDs = [item.id]
        #expect(vm.selectedItemIDs.count == 1)

        vm.selectedItemIDs.remove(item.id)
        #expect(vm.selectedItemIDs.isEmpty)

        settings.resetAll()
    }

    @Test func multiSelectModeToggles() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        #expect(vm.isMultiSelectMode == false)

        vm.toggleMultiSelect()
        #expect(vm.isMultiSelectMode == true)

        vm.toggleMultiSelect()
        #expect(vm.isMultiSelectMode == false)
        #expect(vm.selectedItemIDs.isEmpty)

        settings.resetAll()
    }

    @Test func selectAllSelectsAllFiltered() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        vm.selectAll()
        #expect(vm.selectedItemIDs.count == 3)

        settings.resetAll()
    }

    @Test func deleteSelectedRemovesSelectedItems() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        let firstItem = vm.filteredItems.first!
        vm.selectedItemIDs = [firstItem.id]
        vm.isMultiSelectMode = true

        vm.deleteSelected()
        #expect(vm.isMultiSelectMode == false)
        #expect(vm.selectedItemIDs.isEmpty)
        #expect(vm.filteredItems.count == 2)

        settings.resetAll()
    }

    @Test func copyItemUpdatesStats() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        let item = vm.filteredItems.first!
        let beforeCount = item.pasteCount
        let beforeTimestamp = item.timestamp

        vm.copyItem(item)

        #expect(item.pasteCount == beforeCount + 1)
        #expect(item.lastPastedAt != nil)
        #expect(vm.lastCopiedItemID == item.id)
        // timestamp should be updated (bumped to top)
        #expect(item.timestamp >= beforeTimestamp)

        settings.resetAll()
    }

    @Test func editTextUpdatesContent() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        let textItem = vm.filteredItems.first(where: { $0.contentTypeRaw == "text" })!
        vm.editText(textItem, content: "Updated Content")

        #expect(textItem.textContent == "Updated Content")

        settings.resetAll()
    }

    @Test func togglePinFlipsPinnedStatus() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        let item = vm.filteredItems.first!
        let before = item.isPinned

        vm.togglePin(item)
        #expect(item.isPinned == !before)

        vm.togglePin(item)
        #expect(item.isPinned == before)

        settings.resetAll()
    }

    @Test func handleEscapeClearsSearchFirst() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        vm.searchText = "test"
        vm.handleEscape()
        #expect(vm.searchText.isEmpty)

        settings.resetAll()
    }

    @Test func handleEscapeExitsMultiSelect() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        vm.toggleMultiSelect()
        vm.handleEscape()
        #expect(vm.isMultiSelectMode == false)

        settings.resetAll()
    }

    @Test func moveSelectionDownAdvances() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        let items = vm.filteredItems
        vm.selectedItemIDs = [items.first!.id]
        vm.moveSelectionDown()

        #expect(vm.selectedItemIDs.first != items.first!.id)
        #expect(vm.selectedItemIDs.count == 1)

        settings.resetAll()
    }

    @Test func moveSelectionUpFromFirstStaysAtFirst() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        var items = vm.filteredItems
        vm.selectedItemIDs = [items.first!.id]

        // Move up from first item should stay at first
        vm.moveSelectionUp()
        #expect(vm.selectedItemIDs.first != nil)

        settings.resetAll()
    }

    @Test func confirmSelectionCopiesSelected() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        let items = vm.filteredItems
        vm.selectedItemIDs = [items.first!.id]

        let beforeCount = items.first!.pasteCount
        vm.confirmSelection()

        #expect(vm.lastCopiedItemID == items.first!.id)
        #expect(items.first!.pasteCount == beforeCount + 1)

        settings.resetAll()
    }
}
```

- [ ] **Step 2: 添加到 Xcode 测试 target**

```bash
ruby -e "
require 'xcodeproj'
project = Xcodeproj::Project.open('Mini Capsule.xcodeproj')
target = project.targets.find { |t| t.name == 'Mini CapsuleTests' }
group = project.main_group.find_subpath('Mini CapsuleTests', true)
file_ref = group.new_file('ClipboardListViewModelTests.swift')
target.source_build_phase.add_file_reference(file_ref)
project.save
puts 'Added ClipboardListViewModelTests.swift to test target'
"
```

- [ ] **Step 3: 运行测试**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:Mini_CapsuleTests/ClipboardListViewModelTests test 2>&1 | grep -E "(Test|PASS|FAIL|✓|✗)"
```

Expected: all tests pass.

- [ ] **Step 4: 提交**

```bash
git add "Mini CapsuleTests/ClipboardListViewModelTests.swift" "Mini Capsule.xcodeproj/project.pbxproj"
git commit -m "test: add ClipboardListViewModelTests (search, filter, selection, actions, keyboard)"
```

---

### Task 19: 辅助 Tests — KeyboardEventHandler, PasteService, ColorHex

**Files:**
- Create: `Mini CapsuleTests/ColorHexTests.swift`
- Create: `Mini CapsuleTests/PasteServiceTests.swift`
- Modify: `Mini Capsule.xcodeproj` (add to test target)

- [ ] **Step 1: 创建 ColorHexTests.swift**

```swift
// Mini CapsuleTests/ColorHexTests.swift
import Testing
import SwiftUI
@testable import Mini_Capsule

struct ColorHexTests {

    @Test func validHexParsesCorrectly() async throws {
        let color = Color(hex: "#FF0000")
        #expect(color != nil)
    }

    @Test func validSixCharHexParses() async throws {
        let color = Color(hex: "00FF00")
        #expect(color != nil)
    }

    @Test func invalidHexReturnsNil() async throws {
        let color = Color(hex: "GGGGGG")
        #expect(color == nil)
    }

    @Test func shortHexReturnsNil() async throws {
        let color = Color(hex: "FFF")
        #expect(color == nil)
    }

    @Test func toHexReturnsFormattedHex() async throws {
        let color = Color(hex: "#007AFF")
        #expect(color != nil)
        let hex = color?.toHex()
        #expect(hex?.hasPrefix("#") == true)
        #expect(hex?.count == 7)
    }
}
```

- [ ] **Step 2: 创建 PasteServiceTests.swift**

```swift
// Mini CapsuleTests/PasteServiceTests.swift
import Testing
import AppKit
@testable import Mini_Capsule

struct PasteServiceTests {

    @Test func keyCodeForVReturnsNonZero() async throws {
        let keyCode = PasteService.keyCodeForV()
        // Should return a valid key code (>0) or the fallback 0x09
        #expect(keyCode != 0)
    }

    @Test func isSelfPasteDefaultsToFalse() async throws {
        #expect(PasteService.isSelfPaste == false)
    }
}
```

- [ ] **Step 3: 添加到 Xcode 测试 target**

```bash
ruby -e "
require 'xcodeproj'
project = Xcodeproj::Project.open('Mini Capsule.xcodeproj')
target = project.targets.find { |t| t.name == 'Mini CapsuleTests' }
group = project.main_group.find_subpath('Mini CapsuleTests', true)
[group.new_file('ColorHexTests.swift'), group.new_file('PasteServiceTests.swift')].each do |ref|
  target.source_build_phase.add_file_reference(ref)
end
project.save
puts 'Added test files'
"
```

- [ ] **Step 4: 运行新测试**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:Mini_CapsuleTests/ColorHexTests -only-testing:Mini_CapsuleTests/PasteServiceTests test 2>&1 | grep -E "(Test|PASS|FAIL)"
```

Expected: all tests pass.

- [ ] **Step 5: 提交**

```bash
git add "Mini CapsuleTests/ColorHexTests.swift" "Mini CapsuleTests/PasteServiceTests.swift" "Mini Capsule.xcodeproj/project.pbxproj"
git commit -m "test: add ColorHexTests and PasteServiceTests (B6, B7 verification)"
```

---

### Task 20: 运行完整测试套件 + 最终验证

- [ ] **Step 1: 运行全部测试**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: ALL tests pass, including:
- SettingsStoreTests (existing)
- SettingsKeyTests (existing)
- NotificationNamesTests (existing)
- CapsuleViewModelTests (new)
- ClipboardListViewModelTests (new)
- ColorHexTests (new)
- PasteServiceTests (new)
- CapsuleWindowControllerTests (existing, may need minor updates for SettingsStore changes)

- [ ] **Step 2: 修复任何测试失败**

If existing tests fail due to SettingsStore @Observable migration, update them:
- Replace `store.objectWillChange.sink { ... }` patterns with `withObservationTracking`
- Verify all `SettingsKey.capsuleWindowFrameKey` references are updated to `SettingsKey.capsuleWindowFrame.rawValue`

- [ ] **Step 3: macOS 构建最终验证**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 4: 提交（如有修改）**

```bash
git add -A
git commit -m "test: final test suite integration and fixes"
```

---

## Summary

| Phase | Tasks | Files Created | Files Modified |
|-------|-------|---------------|----------------|
| Foundation | 1-4 | ColorHex.swift | SettingsKey, SettingsStore, SettingsProtocol, ClipItem, AppearanceSettingsView |
| Bug Fixes | 5-6 | — | PasteService, CapsuleWindowController, CapsuleAppDelegate, MenuBarService |
| ViewModels | 7-8 | CapsuleViewModel, ClipboardListViewModel | — |
| View Refactors | 9-11 | KeyboardEventHandler | CapsuleView, CapsuleExpandedView, CapsuleWindowController, NotificationNames |
| Enhancements | 12-16 | CopyFeedbackView, PopoverEditorView | CapsuleCollapsedView, ClipItemRow, CapsuleExpandedView |
| Tests | 17-19 | CapsuleViewModelTests, ClipboardListViewModelTests, ColorHexTests, PasteServiceTests | — |
| Final | 20 | — | — |

**Total:** 12 new files, ~12 modified files, 20 tasks, all independently testable.
