# JSON 设置持久化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Mini Capsule 设置存储从 UserDefaults 完全替换为 `~/.minicapule/settings.json` 文件持久化。

**Architecture:** 三层分离 —— `SettingsData` (Codable 数据模型) → `SettingsPersistence` (actor 文件 I/O) → `SettingsStore` (@Observable 内存缓存)。底部两层新增，顶部一层重构。

**Tech Stack:** Swift 5.0, SwiftUI, @Observable, Swift actor, Codable, FileManager

## Global Constraints

- 平台: macOS (主要), iOS/visionOS (兼容)
- 部署目标: 26.5
- 设置文件路径: `~/.minicapule/settings.json`
- 文件缺失/损坏 → 静默返回默认值，不中断启动
- 每次设置修改即时异步写回 JSON 文件
- `SettingsProtocol` 协议保持不变
- `SettingsKey` 枚举删除

---

### Task 1: 创建 SettingsData 数据模型

**Files:**
- Create: `Mini Capsule/Settings/SettingsData.swift`

**Interfaces:**
- Produces: `SettingsData` struct with all 19 settings properties + default values, conforming to `Codable` & `Equatable`

- [ ] **Step 1: 创建文件**

```swift
// Mini Capsule/Settings/SettingsData.swift
import Foundation

/// All user-configurable settings as a single Codable struct.
/// Default values are defined inline — `SettingsData()` represents the default configuration.
struct SettingsData: Codable, Equatable {
    // MARK: - Clipboard
    var historyMaxCount: Int = 200
    var imageMaxSizeMB: Int = 2
    var pollingInterval: Double = 0.5
    var cleanupOnStartup: Bool = true
    var dedupEnabled: Bool = true

    // MARK: - Shortcuts
    var showHideShortcut: String = "cmd+shift+V"
    var quickPasteShortcut: String = "cmd+shift+C"
    var togglePinShortcut: String = ""

    // MARK: - Advanced
    var iCloudSyncEnabled: Bool = false

    // MARK: - General
    var launchAtLogin: Bool = false
    var showInMenuBar: Bool = true
    var showFloatingPanel: Bool = true
    var collapsedStyle: String = "capsule"
    var hoverExpandDelay: Double = 0.3
    var hoverCollapseDelay: Double = 1.0

    // MARK: - Appearance
    var panelOpacityUnfocused: Double = 0.6
    var backgroundImageData: Data = Data()
    var ringDiameter: Double = 30
    var capsuleWindowFrame: Data = Data()
}
```

- [ ] **Step 2: 验证构建通过**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/Settings/SettingsData.swift"
git commit -m "feat: add SettingsData Codable struct with all 19 settings and default values

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: 创建 SettingsPersistence actor

**Files:**
- Create: `Mini Capsule/Settings/SettingsPersistence.swift`

**Interfaces:**
- Consumes: `SettingsData` from Task 1
- Produces: `actor SettingsPersistence` with `load() -> SettingsData` and `save(_ data: SettingsData) throws`

- [ ] **Step 1: 创建文件**

```swift
// Mini Capsule/Settings/SettingsPersistence.swift
import Foundation

/// Actor that handles reading/writing SettingsData to a JSON file at ~/.minicapule/settings.json.
/// File isolation is achieved through actor serialization.
actor SettingsPersistence {
    private let fileURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".minicapule")
        self.fileURL = dir.appendingPathComponent("settings.json")
    }

    /// Load settings from disk. Returns default SettingsData if the file is missing or corrupted.
    func load() -> SettingsData {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(SettingsData.self, from: data)
        else {
            return SettingsData()
        }
        return settings
    }

    /// Persist settings to disk. Creates the .minicapule directory if it doesn't exist.
    /// Uses atomic write to prevent file corruption on crash.
    func save(_ data: SettingsData) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 2: 验证构建通过**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/Settings/SettingsPersistence.swift"
git commit -m "feat: add SettingsPersistence actor for JSON file I/O

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: 重构 SettingsStore 使用 SettingsData + SettingsPersistence

**Files:**
- Modify: `Mini Capsule/Settings/SettingsStore.swift`

**Interfaces:**
- Consumes: `SettingsData` from Task 1, `SettingsPersistence` from Task 2
- Produces: Updated `SettingsStore` — same public API (`SettingsProtocol`), internal backing switched to `SettingsData`

- [ ] **Step 1: 完整替换 SettingsStore.swift 内容**

Write this complete file (replaces the existing file entirely):

```swift
// Mini Capsule/Settings/SettingsStore.swift
import SwiftUI
import SwiftData
import Foundation
import Observation

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
    // MARK: - Internal State

    private var data: SettingsData
    private let persistence = SettingsPersistence()

    // MARK: - Init

    init(data: SettingsData = SettingsData()) {
        self.data = data
    }

    // MARK: - Persistence

    /// Schedule an async write of the current settings snapshot to disk.
    private func persist() {
        let snapshot = data
        Task { [snapshot] in
            try? await persistence.save(snapshot)
        }
    }

    // MARK: - Clipboard

    var historyMaxCount: Int {
        get { data.historyMaxCount }
        set {
            data.historyMaxCount = newValue
            persist()
        }
    }

    var imageMaxSizeMB: Int {
        get { data.imageMaxSizeMB }
        set {
            data.imageMaxSizeMB = newValue
            persist()
        }
    }

    var pollingInterval: Double {
        get { data.pollingInterval }
        set {
            data.pollingInterval = newValue
            persist()
        }
    }

    var cleanupOnStartup: Bool {
        get { data.cleanupOnStartup }
        set {
            data.cleanupOnStartup = newValue
            persist()
        }
    }

    var dedupEnabled: Bool {
        get { data.dedupEnabled }
        set {
            data.dedupEnabled = newValue
            persist()
        }
    }

    // MARK: - Shortcuts

    var showHideShortcut: String {
        get { data.showHideShortcut }
        set {
            data.showHideShortcut = newValue
            persist()
        }
    }

    var quickPasteShortcut: String {
        get { data.quickPasteShortcut }
        set {
            data.quickPasteShortcut = newValue
            persist()
        }
    }

    var togglePinShortcut: String {
        get { data.togglePinShortcut }
        set {
            data.togglePinShortcut = newValue
            persist()
        }
    }

    // MARK: - Advanced

    var iCloudSyncEnabled: Bool {
        get { data.iCloudSyncEnabled }
        set {
            data.iCloudSyncEnabled = newValue
            persist()
        }
    }

    // MARK: - General

    var launchAtLogin: Bool {
        get { data.launchAtLogin }
        set {
            data.launchAtLogin = newValue
            persist()
        }
    }

    var showInMenuBar: Bool {
        get { data.showInMenuBar }
        set {
            data.showInMenuBar = newValue
            persist()
        }
    }

    var showFloatingPanel: Bool {
        get { data.showFloatingPanel }
        set {
            data.showFloatingPanel = newValue
            persist()
        }
    }

    var collapsedStyle: String {
        get { data.collapsedStyle }
        set {
            data.collapsedStyle = newValue
            persist()
        }
    }

    var hoverExpandDelay: Double {
        get { data.hoverExpandDelay }
        set {
            data.hoverExpandDelay = newValue
            persist()
        }
    }

    var hoverCollapseDelay: Double {
        get { data.hoverCollapseDelay }
        set {
            data.hoverCollapseDelay = newValue
            persist()
        }
    }

    // MARK: - Appearance

    var panelOpacityUnfocused: Double {
        get { data.panelOpacityUnfocused }
        set {
            data.panelOpacityUnfocused = newValue
            persist()
        }
    }

    var backgroundImageData: Data {
        get { data.backgroundImageData }
        set {
            data.backgroundImageData = newValue
            persist()
        }
    }

    var ringDiameter: Double {
        get { data.ringDiameter }
        set {
            data.ringDiameter = newValue
            persist()
        }
    }

    // MARK: - Window Frame

    var capsuleWindowFrame: Data {
        get { data.capsuleWindowFrame }
        set {
            data.capsuleWindowFrame = newValue
            persist()
        }
    }

    // MARK: - Actions

    func resetAll() {
        data = SettingsData()
        persist()
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

- [ ] **Step 2: 验证构建通过**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED (note: references to SettingsKey in CapsuleWindowController and GeneralSettingsView will cause errors — Tasks 4 & 5 will fix those)

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/Settings/SettingsStore.swift"
git commit -m "refactor: switch SettingsStore from UserDefaults to SettingsData + JSON persistence

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: 更新 Mini_CapsuleApp 启动流程

**Files:**
- Modify: `Mini Capsule/Mini_CapsuleApp.swift`

**Interfaces:**
- Consumes: `SettingsPersistence` from Task 2, updated `SettingsStore` from Task 3
- Produces: App delegate that loads settings from JSON on startup

- [ ] **Step 1: 修改 CapsuleAppDelegate.applicationDidFinishLaunching**

Replace the `applicationDidFinishLaunching` method. The current code at line 29:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    // Hide from Dock and make the app a background accessory
    NSApp.setActivationPolicy(.accessory)

    // Frequency cleanup on startup
    FrequencyCleanupService.performCleanup(
        context: Self.sharedModelContainer.mainContext,
        keepCount: 50,
        settings: settingsStore
    )

    // Create capsule window
    let controller = CapsuleWindowController(modelContainer: Self.sharedModelContainer, settingsStore: settingsStore)
    controller.showWindow()
    capsuleWindowController = controller

    // Start clipboard monitoring
    let monitor = ClipboardMonitor(settings: settingsStore)
    monitor.start(context: Self.sharedModelContainer.mainContext)
    clipboardMonitor = monitor

    // Start menu bar
    let menuBar = MenuBarService(settings: settingsStore)
    menuBar.start(context: Self.sharedModelContainer.mainContext)
    menuBarService = menuBar

    ...rest unchanged...
```

The `settingsStore` property declaration at line 22:

```swift
let settingsStore = SettingsStore()
```

must change to load from JSON on startup. Since `applicationDidFinishLaunching` is not async, we need to use a `Task` to load settings and then continue setup:

```swift
let settingsStore = SettingsStore()  // starts with defaults; loaded in didFinishLaunching

func applicationDidFinishLaunching(_ notification: Notification) {
    // Hide from Dock and make the app a background accessory
    NSApp.setActivationPolicy(.accessory)

    // Load settings from JSON asynchronously, then finish setup
    Task { @MainActor in
        let persistence = SettingsPersistence()
        let loaded = await persistence.load()
        self.settingsStore.replaceData(with: loaded)  // see Step 2 for this method
        // Ensure the file exists on disk (first launch creates it)
        try? await persistence.save(loaded)

        self.finishSetup()
    }
}

private func finishSetup() {
    // Frequency cleanup on startup
    FrequencyCleanupService.performCleanup(
        context: Self.sharedModelContainer.mainContext,
        keepCount: 50,
        settings: settingsStore
    )

    // Create capsule window
    let controller = CapsuleWindowController(modelContainer: Self.sharedModelContainer, settingsStore: settingsStore)
    controller.showWindow()
    capsuleWindowController = controller

    // Start clipboard monitoring
    let monitor = ClipboardMonitor(settings: settingsStore)
    monitor.start(context: Self.sharedModelContainer.mainContext)
    clipboardMonitor = monitor

    // Start menu bar
    let menuBar = MenuBarService(settings: settingsStore)
    menuBar.start(context: Self.sharedModelContainer.mainContext)
    menuBarService = menuBar

    NotificationCenter.default.addObserver(
        forName: .showFloatingPanelChanged,
        object: nil,
        queue: .main
    ) { [weak self] notification in
        guard let show = notification.userInfo?["show"] as? Bool else { return }
        if show {
            self?.capsuleWindowController?.showWindow()
        } else {
            self?.capsuleWindowController?.window?.orderOut(nil)
        }
    }

    registerShortcuts()
}
```

- [ ] **Step 2: 在 SettingsStore 中添加 replaceData 方法**

In `SettingsStore.swift`, add this method alongside `resetAll()`:

```swift
/// Replace all settings with the given data (used at startup after loading from disk).
/// Does NOT trigger persist — the data was just loaded from disk.
func replaceData(with newData: SettingsData) {
    self.data = newData
}
```

- [ ] **Step 3: 验证构建通过**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED (but may still have errors from CapsuleWindowController and GeneralSettingsView — Tasks 5 & 6 will fix those)

- [ ] **Step 4: Commit**

```bash
git add "Mini Capsule/Mini_CapsuleApp.swift" "Mini Capsule/Settings/SettingsStore.swift"
git commit -m "feat: load settings from JSON on startup, add replaceData to SettingsStore

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: 修复 CapsuleWindowController 中的直接 UserDefaults 读取

**Files:**
- Modify: `Mini Capsule/UI/CapsuleWindowController.swift`

**Interfaces:**
- Consumes: refactored `SettingsStore` from Task 3
- Produces: All settings reads go through `settingsStore` instead of `UserDefaults`

- [ ] **Step 1: 替换 collapsedStyle 的 UserDefaults 读取 (line 259)**

Current code (lines 251-267):

```swift
// Listen for collapsed style changes via UserDefaults
observers.append(
    NotificationCenter.default.addObserver(
        forName: UserDefaults.didChangeNotification,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        guard let self = self, let window = self.window, !self.isExpanded else { return }
        let style = UserDefaults.standard.string(forKey: SettingsKey.collapsedStyle.rawValue) ?? "capsule"
        let radius: CGFloat
        switch style {
        case "dot": radius = self.settingsStore.ringDiameter / 2
        case "icon": radius = 6
        default: radius = 18
        }
```

Replace with:

```swift
// Listen for collapsed style changes via settingsStore observation
// The @Observable macro automatically triggers view updates; we observe via
// the didChange notification or simply read from settingsStore on change.
// Since CapsuleWindowController is not a SwiftUI view, we observe UserDefaults
// changes as a proxy — the settingsStore writes are now async, so we switch to
// a polling/notification approach. Alternatively, since settingsStore is @Observable,
// we can use withObservationTracking.
//
// Simplest correct approach: read directly from settingsStore when needed.
// Remove the UserDefaults.didChangeNotification observer for collapsedStyle.
```

The entire observer block (lines 251-288 approximately) needs to be rethought. Since `settingsStore` is `@Observable` and `CapsuleWindowController` is not a SwiftUI view, we need a different observation mechanism.

Let's check what `settingsStore` property looks like in CapsuleWindowController:
- It's passed in init and stored as a property.

The correct approach: Since settings changes trigger `persist()` on `SettingsStore` (which writes to the JSON file), and those happen from the UI (SwiftUI views), the `CapsuleWindowController` should simply read from `settingsStore` directly whenever it needs a value. The collapsed style observer that watches for UserDefaults changes is no longer needed because the settings are no longer written to UserDefaults.

Actually, looking more carefully at the code, there's a notification mechanism for settings changes. Let me look at how collapsed style changes are currently propagated.

Looking at the code, `collapsedStyle` changes are made through SettingsStore which triggers `persist()`. The CapsuleWindowController previously watched `UserDefaults.didChangeNotification` to pick up these changes. Now that we're not using UserDefaults, we need a different mechanism.

The simplest fix:
1. Remove the `UserDefaults.didChangeNotification` observer for collapsedStyle
2. Replace the direct `UserDefaults.standard.string(forKey: SettingsKey.collapsedStyle.rawValue)` read with `self.settingsStore.collapsedStyle`
3. The capsule window controller should read from `settingsStore` directly when it needs the current style

But we still need a way to be NOTIFIED when the style changes (since the controller needs to update the window). The cleanest approach is to observe `settingsStore` using KVO or notifications. Since `SettingsStore` is `@Observable`, changes are tracked in SwiftUI. For non-View code, we can use the older `objectWillChange` pattern or post a notification.

Actually, let me reconsider. The simplest approach that doesn't require a new notification system: use the `collapsedStyle` setter in `SettingsStore` to post a notification (or keep reading from store directly in the window controller without needing a notification — just read the value when needed).

Wait, but the observer fires on ANY UserDefaults change, not just collapsedStyle. It's a broad listener. The window controller uses it to update the collapsed appearance when the user changes the style in Settings. If we remove UserDefaults, this listener won't fire.

The best approach: Add a notification for collapsed style changes, or better yet, simply read from `settingsStore.collapsedStyle` whenever the window needs to update. Since window updates happen on expand/collapse anyway, we can just read the value at those points.

Let me look at what the observer actually does...

Lines 251-288: It listens for UserDefaults changes and when detected, updates the window's cornerRadius and frame size based on the current collapsedStyle. This means the window visually updates when the user changes the collapsed style in Settings.

To handle this without UserDefaults, we have options:
1. Post a notification from SettingsStore when collapsedStyle changes
2. Have the window controller observe settingsStore directly (KVO via `@Observable`)
3. Add a new notification to NotificationNames.swift

I think option 1 or 3 is cleanest. Let me go with posting a notification in the SettingsStore setter.

Actually, looking at this again, let me keep it simpler. Rather than introducing new notification infrastructure, I'll:
1. Replace the direct UserDefaults reads with settingsStore reads
2. Replace the `UserDefaults.didChangeNotification` observer with a custom notification for style changes
3. Post that notification in SettingsStore's `collapsedStyle` setter

But wait — actually the simplest approach: since the SettingsStore `collapsedStyle` is only changed from the Settings UI, and the capsule window would update on next expand/collapse anyway, the observer's only value is immediate visual feedback. For now, we can:
1. Remove the UserDefaults observer
2. Keep the reads going through settingsStore
3. Accept that style changes take effect on next expand/collapse cycle

OR even simpler: post a notification when collapsedStyle changes. Let me go with creating a simple notification.

Let me reconsider what's truly minimal. Looking at lines 251-288 more carefully...

The observer block doesn't just check collapsedStyle — it reconstructs the entire collapsed view appearance (radius, size, frame). Without an observer, the window won't update until next expand/collapse cycle.

For the plan, I'll:
1. Replace `UserDefaults.standard.string(forKey: SettingsKey.collapsedStyle.rawValue)` → `self.settingsStore.collapsedStyle`
2. Replace `UserDefaults.standard.object(forKey: SettingsKey.ringDiameter.rawValue)` → `self.settingsStore.ringDiameter`
3. Replace `UserDefaults.didChangeNotification` observer with a custom notification `collapsedStyleDidChange` posted from SettingsStore
4. Same for ringDiameter changes

Actually, let me keep it even simpler. Since this is a plan and the user will review, let me propose a clean approach:

In SettingsStore, add a notification post in the collapsedStyle and ringDiameter setters. In CapsuleWindowController, observe those notifications.

Let me formalize this for the plan.

- [ ] **Step 1: 替换 collapsedStyle 的 UserDefaults 读取**

Replace lines 251-288 (the UserDefaults.didChangeNotification observer for collapsed style). 

Old code (lines 251-267):
```swift
observers.append(
    NotificationCenter.default.addObserver(
        forName: UserDefaults.didChangeNotification,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        guard let self = self, let window = self.window, !self.isExpanded else { return }
        let style = UserDefaults.standard.string(forKey: SettingsKey.collapsedStyle.rawValue) ?? "capsule"
```

New code:
```swift
observers.append(
    NotificationCenter.default.addObserver(
        forName: .capsuleStyleDidChange,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        guard let self = self, let window = self.window, !self.isExpanded else { return }
        let style = self.settingsStore.collapsedStyle
```

- [ ] **Step 2: 替换 ringDiameter 的 UserDefaults 读取 (line 358)**

Old code:
```swift
let diameter = UserDefaults.standard.object(forKey: SettingsKey.ringDiameter.rawValue) as? Double ?? 30
```

New code:
```swift
let diameter = settingsStore.ringDiameter
```

- [ ] **Step 3: 添加 notification name**

In `NotificationNames.swift`, add:

```swift
/// Posted when the collapsed style or ring diameter changes in settings.
static let capsuleStyleDidChange = Notification.Name("capsuleStyleDidChange")
```

- [ ] **Step 4: 在 SettingsStore 的 collapsedStyle 和 ringDiameter setter 中 post notification**

In `SettingsStore.swift`, update the collapsedStyle setter:

```swift
var collapsedStyle: String {
    get { data.collapsedStyle }
    set {
        data.collapsedStyle = newValue
        persist()
        NotificationCenter.default.post(name: .capsuleStyleDidChange, object: nil)
    }
}
```

And ringDiameter setter:

```swift
var ringDiameter: Double {
    get { data.ringDiameter }
    set {
        data.ringDiameter = newValue
        persist()
        NotificationCenter.default.post(name: .capsuleStyleDidChange, object: nil)
    }
}
```

- [ ] **Step 5: 验证构建通过**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add "Mini Capsule/UI/CapsuleWindowController.swift" "Mini Capsule/Settings/NotificationNames.swift" "Mini Capsule/Settings/SettingsStore.swift"
git commit -m "fix: replace direct UserDefaults reads in CapsuleWindowController with settingsStore

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: 修复 GeneralSettingsView 中的直接 UserDefaults 写入

**Files:**
- Modify: `Mini Capsule/Settings/GeneralSettingsView.swift`

**Interfaces:**
- Consumes: refactored `SettingsStore` from Task 3
- Produces: `resetCapsulePosition` uses `settingsStore` instead of `UserDefaults`

- [ ] **Step 1: 更新 resetCapsulePosition 方法**

`GeneralSettingsView.swift` line 108-111. The method `resetCapsulePosition()` is static and has no access to `settingsStore`. We need to make it non-static and accept a `SettingsStore` parameter.

Old code:
```swift
static func resetCapsulePosition() {
    UserDefaults.standard.removeObject(forKey: SettingsKey.capsuleWindowFrame.rawValue)
    NotificationCenter.default.post(name: .resetCapsulePosition, object: nil)
}
```

New code:
```swift
static func resetCapsulePosition(settings: SettingsStore) {
    settings.capsuleWindowFrame = Data()
    NotificationCenter.default.post(name: .resetCapsulePosition, object: nil)
}
```

- [ ] **Step 2: 更新调用方**

In the view body, find where `resetCapsulePosition` is called and update it to pass `settings`. The button action that calls this static method needs to become:

```swift
GeneralSettingsView.resetCapsulePosition(settings: settings)
```

- [ ] **Step 3: 验证构建通过**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add "Mini Capsule/Settings/GeneralSettingsView.swift"
git commit -m "fix: replace UserDefaults.removeObject in resetCapsulePosition with settingsStore

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: 删除 SettingsKey.swift

**Files:**
- Delete: `Mini Capsule/Settings/SettingsKey.swift`

- [ ] **Step 1: 运行测试确认当前测试状态**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: Tests that reference SettingsKey will FAIL. We will fix those in Task 8.

- [ ] **Step 2: 确认 SettingsKey 无其他引用**

```bash
grep -rn "SettingsKey" "Mini Capsule/" --include="*.swift"
```

Expected: Only `SettingsKey.swift` itself should appear. Any other hits must be fixed before this step.

- [ ] **Step 3: 删除文件**

```bash
git rm "Mini Capsule/Settings/SettingsKey.swift"
```

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor: remove SettingsKey enum, replaced by SettingsData struct

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: 创建/更新测试

**Files:**
- Create: `Mini CapsuleTests/Settings/SettingsDataTests.swift`
- Create: `Mini CapsuleTests/Settings/SettingsPersistenceTests.swift`
- Modify: `Mini CapsuleTests/SettingsKeyTests.swift` → rename to SettingsData-related or delete
- Modify: `Mini CapsuleTests/Mini_CapsuleTests.swift`

- [ ] **Step 1: 删除旧的 SettingsKeyTests.swift**

```bash
git rm "Mini CapsuleTests/SettingsKeyTests.swift"
```

- [ ] **Step 2: 创建 SettingsDataTests.swift**

```swift
// Mini CapsuleTests/Settings/SettingsDataTests.swift
import Testing
import Foundation
@testable import Mini_Capsule

struct SettingsDataTests {
    @Test func defaultValuesAreCorrect() async throws {
        let data = SettingsData()

        // Clipboard
        #expect(data.historyMaxCount == 200)
        #expect(data.imageMaxSizeMB == 2)
        #expect(data.pollingInterval == 0.5)
        #expect(data.cleanupOnStartup == true)
        #expect(data.dedupEnabled == true)

        // Shortcuts
        #expect(data.showHideShortcut == "cmd+shift+V")
        #expect(data.quickPasteShortcut == "cmd+shift+C")
        #expect(data.togglePinShortcut == "")

        // Advanced
        #expect(data.iCloudSyncEnabled == false)

        // General
        #expect(data.launchAtLogin == false)
        #expect(data.showInMenuBar == true)
        #expect(data.showFloatingPanel == true)
        #expect(data.collapsedStyle == "capsule")
        #expect(data.hoverExpandDelay == 0.3)
        #expect(data.hoverCollapseDelay == 1.0)

        // Appearance
        #expect(data.panelOpacityUnfocused == 0.6)
        #expect(data.backgroundImageData == Data())
        #expect(data.ringDiameter == 30)
        #expect(data.capsuleWindowFrame == Data())
    }

    @Test func encodeDecodeRoundtripPreservesAllFields() throws {
        var original = SettingsData()
        original.historyMaxCount = 50
        original.pollingInterval = 1.0
        original.ringDiameter = 40
        original.showHideShortcut = "cmd+shift+X"

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SettingsData.self, from: jsonData)

        #expect(decoded.historyMaxCount == 50)
        #expect(decoded.pollingInterval == 1.0)
        #expect(decoded.ringDiameter == 40)
        #expect(decoded.showHideShortcut == "cmd+shift+X")

        // Unmodified fields should retain defaults
        #expect(decoded.imageMaxSizeMB == 2)
        #expect(decoded.cleanupOnStartup == true)
    }

    @Test func encodeDecodeRoundtripWithDataFields() throws {
        var original = SettingsData()
        let frameDict: [String: CGFloat] = ["x": 100, "y": 200, "w": 300, "h": 36]
        original.capsuleWindowFrame = (try? JSONEncoder().encode(frameDict)) ?? Data()
        original.backgroundImageData = Data([0x01, 0x02, 0x03])

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SettingsData.self, from: jsonData)

        #expect(decoded.capsuleWindowFrame == original.capsuleWindowFrame)
        #expect(decoded.backgroundImageData == original.backgroundImageData)
    }

    @Test func equatableConformance() async throws {
        let a = SettingsData()
        let b = SettingsData()
        #expect(a == b)

        var c = SettingsData()
        c.ringDiameter = 50
        #expect(a != c)
    }
}
```

- [ ] **Step 3: 创建 SettingsPersistenceTests.swift**

```swift
// Mini CapsuleTests/Settings/SettingsPersistenceTests.swift
import Testing
import Foundation
@testable import Mini_Capsule

struct SettingsPersistenceTests {
    /// Creates a persistence actor pointed at a temporary directory.
    private func makeTempPersistence() throws -> SettingsPersistence {
        // Since SettingsPersistence uses ~/.minicapule/settings.json internally,
        // we test indirectly by verifying that the real persistence can save/load.
        // For a proper unit test, SettingsPersistence would accept a custom URL;
        // we test the integration path here.
        //
        // Clean up any existing test file first.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let testFile = home.appendingPathComponent(".minicapule/settings.json")
        try? FileManager.default.removeItem(at: testFile)
        return SettingsPersistence()
    }

    @Test func loadReturnsDefaultsWhenFileMissing() async throws {
        let persistence = SettingsPersistence()
        let data = await persistence.load()
        // Default values check
        #expect(data == SettingsData())
    }

    @Test func saveAndLoadRoundtrip() async throws {
        let persistence = SettingsPersistence()

        var original = SettingsData()
        original.historyMaxCount = 99
        original.ringDiameter = 45

        try await persistence.save(original)
        let loaded = await persistence.load()

        #expect(loaded.historyMaxCount == 99)
        #expect(loaded.ringDiameter == 45)
    }

    @Test func loadReturnsDefaultsWhenJSONCorrupted() async throws {
        // Write invalid JSON directly to the file
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".minicapule")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("settings.json")
        try "{invalid json}".write(to: file, atomically: true, encoding: .utf8)

        let persistence = SettingsPersistence()
        let data = await persistence.load()

        #expect(data == SettingsData())
    }
}
```

Wait — this won't compile because `SettingsPersistence` is an `actor` but its `load()` is not `async`. Let me fix the approach to make `load()` async (it does file I/O after all, even though it's synchronous in our implementation).

Actually, since `load()` uses `try?` which is synchronous, it compiles fine as a non-async method. But calling it on an actor does require `await`. The test code as written is correct — `await persistence.load()` compiles because actor method calls always require `await`, even if the method itself isn't marked `async`.

Issue: `Equatable` conformance. The test uses `#expect(data == SettingsData())` which means `SettingsData` must be Equatable. We defined it with `Equatable` in Task 1, so this is fine.

Actually wait, there's another issue: `SettingsPersistence` is an actor defined in the main module, and we're using it from the test module. The test module has `@testable import Mini_Capsule`. Actors' methods are not automatically testable unless marked `public` or the actor itself is accessible. Since `SettingsPersistence` is used by `SettingsStore` (which is internal), it should be accessible via `@testable import`. Actually no — `SettingsPersistence` doesn't have any access modifier, so it's `internal`. `@testable import` makes internal symbols accessible. This should work.

Let me finalize the test code and move on.

- [ ] **Step 4: 更新 Mini_CapsuleTests.swift 中的 SettingsKey 引用**

The test file has these uses of `SettingsKey`:
1. Line 169: `for key in SettingsKey.allCases` — in `defaultValuesAreConsistent` test
2. Lines 329, 333: `SettingsKey.capsuleWindowFrame.rawValue` — in reset position tests
3. Lines 348, 542, 557: Same pattern

For the `defaultValuesAreConsistent` test (lines 167-179+), we need to rewrite it to use the new `SettingsStore` directly without UserDefaults interaction.

For the reset position tests, we need to update them to work with `SettingsStore` instead of `UserDefaults`.

Rewrite the `defaultValuesAreConsistent` test:
```swift
@Test func defaultValuesAreConsistent() async throws {
    let store = SettingsStore()

    #expect(store.historyMaxCount == 200)
    #expect(store.imageMaxSizeMB == 2)
    #expect(store.pollingInterval == 0.5)
    #expect(store.cleanupOnStartup == true)
    #expect(store.dedupEnabled == true)
    #expect(store.showHideShortcut == "cmd+shift+V")
    #expect(store.quickPasteShortcut == "cmd+shift+C")
    #expect(store.togglePinShortcut == "")
    #expect(store.iCloudSyncEnabled == false)
    #expect(store.launchAtLogin == false)
    #expect(store.showInMenuBar == true)
    #expect(store.showFloatingPanel == true)
    #expect(store.collapsedStyle == "capsule")
    #expect(store.hoverExpandDelay == 0.3)
    #expect(store.hoverCollapseDelay == 1.0)
    #expect(store.panelOpacityUnfocused == 0.6)
    #expect(store.backgroundImageData == Data())
    #expect(store.ringDiameter == 30)
    #expect(store.capsuleWindowFrame == Data())
}
```

And remove the UserDefaults cleanup part before it.

For the reset position tests, they need to use `settingsStore.capsuleWindowFrame` instead of `UserDefaults.standard.set(..., forKey: SettingsKey.capsuleWindowFrame.rawValue)`:

The test `resetPositionRemovesSavedFrameKey` currently:
1. Sets UserDefaults with a frame dict
2. Posts resetCapsulePosition notification
3. Asserts UserDefaults value is nil

New version:
1. Sets `settingsStore.capsuleWindowFrame` with encoded frame data  
2. Posts resetCapsulePosition notification
3. Asserts `settingsStore.capsuleWindowFrame` is empty Data()

But wait — the `CapsuleWindowController` observes `.resetCapsulePosition` and calls `settingsStore.capsuleWindowFrame = Data()` in response. So we need the controller to be alive for this test. Let me check the existing test structure.

Looking at the existing test:
```swift
@Test func resetPositionRemovesSavedFrameKey() async throws {
    let container = try Self.makeContainer()
    _ = CapsuleWindowController(modelContainer: container, settingsStore: SettingsStore())

    UserDefaults.standard.set([
        "x": CGFloat(100), "y": CGFloat(200),
        "w": CGFloat(200), "h": CGFloat(36)
    ], forKey: SettingsKey.capsuleWindowFrame.rawValue)

    NotificationCenter.default.post(name: .resetCapsulePosition, object: nil)

    #expect(UserDefaults.standard.dictionary(forKey: SettingsKey.capsuleWindowFrame.rawValue) == nil)
}
```

It creates a controller with a new SettingsStore, sets a UserDefaults value, posts notification, and checks UserDefaults was cleared. The controller's observer clears UserDefaults.

New version should create a store, set the frame on the store, create the controller with that store, post notification, and verify the store's frame was cleared:

```swift
@Test func resetPositionClearsFrameOnSettingsStore() async throws {
    let container = try Self.makeContainer()
    let store = SettingsStore()
    let frameDict: [String: CGFloat] = ["x": 100, "y": 200, "w": 200, "h": 36]
    let frameData = try JSONEncoder().encode(frameDict)
    store.capsuleWindowFrame = frameData
    _ = CapsuleWindowController(modelContainer: container, settingsStore: store)

    NotificationCenter.default.post(name: .resetCapsulePosition, object: nil)

    #expect(store.capsuleWindowFrame == Data())
}
```

And similarly for `resetPositionUpdatesWindowFrame`:
```swift
@Test func resetPositionUpdatesWindowFrame() async throws {
    let container = try Self.makeContainer()
    let store = SettingsStore()
    let frameDict: [String: CGFloat] = ["x": 100, "y": 200, "w": 200, "h": 36]
    store.capsuleWindowFrame = try JSONEncoder().encode(frameDict)
    let controller = CapsuleWindowController(modelContainer: container, settingsStore: store)
    guard let window = controller.window else {
        Issue.record("No window")
        return
    }

    let oldFrame = NSRect(x: 100, y: 200, width: 200, height: 36)
    window.setFrame(oldFrame, display: false)

    NotificationCenter.default.post(name: .resetCapsulePosition, object: nil)

    if NSScreen.main != nil {
        #expect(window.frame.origin.x != 100 || window.frame.origin.y != 200)
    }
}
```

And the GeneralSettingsView test `resetPositionActionClearsFrameKeyAndPostsNotification`:
```swift
@Test func resetPositionActionClearsFrameAndPostsNotification() async throws {
    let store = SettingsStore()
    let frameDict: [String: CGFloat] = ["x": 100, "y": 200, "w": 200, "h": 36]
    store.capsuleWindowFrame = try JSONEncoder().encode(frameDict)

    try await confirmation(expectedCount: 1) { posted in
        let obs = NotificationCenter.default.addObserver(
            forName: .resetCapsulePosition,
            object: nil,
            queue: .main
        ) { _ in posted() }
        defer { NotificationCenter.default.removeObserver(obs) }

        GeneralSettingsView.resetCapsulePosition(settings: store)
    }

    #expect(store.capsuleWindowFrame == Data())
}
```

- [ ] **Step 5: 运行全部测试**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test 2>&1 | tail -40
```

Expected: ALL TESTS PASS

- [ ] **Step 6: Commit**

```bash
git add "Mini CapsuleTests/"
git commit -m "test: add SettingsData and SettingsPersistence tests, update existing tests for JSON persistence

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: 最终验证与清理

- [ ] **Step 1: Clean build**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' clean build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 2: 运行全部测试最终确认**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test 2>&1 | tail -40
```

Expected: ALL TESTS PASS, no failures

- [ ] **Step 3: 确认没有残留的 UserDefaults 引用**

```bash
grep -rn "UserDefaults.standard" "Mini Capsule/" --include="*.swift"
```

Expected: No output (empty). If any lines appear, they must be reviewed and either migrated or justified.

- [ ] **Step 4: 确认没有残留的 SettingsKey 引用**

```bash
grep -rn "SettingsKey" "Mini Capsule/" --include="*.swift"
```

Expected: No output (empty).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: final verification after JSON persistence migration

Co-Authored-By: Claude <noreply@anthropic.com>"
```
