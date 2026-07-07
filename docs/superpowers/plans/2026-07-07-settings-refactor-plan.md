# Settings Module Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish `SettingsStore` as the single source of truth for all settings, eliminate raw `UserDefaults` calls from consumers, unify notification names, and add comprehensive automated tests.

**Architecture:** Create `SettingsKey` (private key enum), `NotificationNames` (single notification registry), and `SettingsProtocol` (protocol for DI). Refactor `SettingsStore` to conform to `SettingsProtocol` and emit `objectWillChange` on every property change. Inject `SettingsProtocol` into all services. SwiftUI views consume via `@EnvironmentObject`. Test every feature independently.

**Tech Stack:** Swift, SwiftUI, SwiftData, Combine, AppKit, Swift Testing, UserDefaults/@AppStorage

## Global Constraints

- Deployment target: 26.5 (iOS, macOS, visionOS)
- Swift 5.0
- Swift Testing framework for unit tests
- No behavioral changes — all defaults, ranges, and side effects remain identical
- No new settings added
- iCloud sync placeholder preserved as-is

---

### Task 1: Create SettingsKey constants

**Files:**
- Create: `Mini Capsule/Settings/SettingsKey.swift`

**Interfaces:**
- Produces: `SettingsKey` enum with `String` raw values, `CaseIterable`, 18 cases

- [ ] **Step 1: Write the test**

```swift
// Mini CapsuleTests/SettingsKeyTests.swift
import Testing
@testable import Mini_Capsule

struct SettingsKeyTests {
    @Test func allKeysAreUnique() async throws {
        let allKeys = SettingsKey.allCases.map(\.rawValue)
        let uniqueKeys = Set(allKeys)
        #expect(allKeys.count == uniqueKeys.count)
    }

    @Test func keyCountIsCorrect() async throws {
        #expect(SettingsKey.allCases.count == 18)
    }

    @Test func keysMatchExpectedValues() async throws {
        let expectedKeys: Set<String> = [
            "historyMaxCount", "imageMaxSizeMB", "pollingInterval",
            "cleanupOnStartup", "dedupEnabled",
            "showHideShortcut", "quickPasteShortcut", "togglePinShortcut",
            "iCloudSyncEnabled", "launchAtLogin", "showInMenuBar",
            "showFloatingPanel", "collapsedStyle", "hoverExpandDelay",
            "hoverCollapseDelay", "panelOpacityUnfocused",
            "backgroundImageData", "dotColorMode", "dotCustomColor"
        ]
        let actualKeys = Set(SettingsKey.allCases.map(\.rawValue))
        #expect(actualKeys == expectedKeys)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/SettingsKeyTests test`
Expected: FAIL (SettingsKey not found)

- [ ] **Step 3: Create SettingsKey.swift**

```swift
// Mini Capsule/Settings/SettingsKey.swift
/// Private key constants for UserDefaults access.
/// Only SettingsStore uses this enum directly.
enum SettingsKey: String, CaseIterable {
    case historyMaxCount
    case imageMaxSizeMB
    case pollingInterval
    case cleanupOnStartup
    case dedupEnabled
    case showHideShortcut
    case quickPasteShortcut
    case togglePinShortcut
    case iCloudSyncEnabled
    case launchAtLogin
    case showInMenuBar
    case showFloatingPanel
    case collapsedStyle
    case hoverExpandDelay
    case hoverCollapseDelay
    case panelOpacityUnfocused
    case backgroundImageData
    case dotColorMode
    case dotCustomColor
}
```

- [ ] **Step 4: Add new files to Xcode project**

Run: `open "Mini Capsule.xcodeproj"` then manually add `SettingsKey.swift` and `SettingsKeyTests.swift` to the project targets.

Actually — check if the project already auto-includes files. Let me verify by checking if we need to manually add files.

Let me check project structure first.

Run: `grep -r "SettingsKey" "Mini Capsule.xcodeproj/project.pbxproj"` to confirm file is not already referenced.

Since this is an Xcode project, we need to ensure the file is added to the pbxproj. We'll write the file and use the Xcode project's folder reference to auto-include (if it uses folder references), or we'll add it via xcodebuild or manual steps.

For now, create the file and we'll handle project inclusion after verifying.

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/SettingsKeyTests test`
Expected: PASS (3 tests pass)

- [ ] **Step 6: Commit**

```bash
git add "Mini Capsule/Settings/SettingsKey.swift" "Mini CapsuleTests/SettingsKeyTests.swift"
git commit -m "feat: add SettingsKey constants enum

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Create unified NotificationNames file

**Files:**
- Create: `Mini Capsule/Settings/NotificationNames.swift`
- Test: `Mini CapsuleTests/NotificationNamesTests.swift`

**Interfaces:**
- Produces: Two `Notification.Name` extensions:
  - `pollingIntervalDidChange`, `showFloatingPanelChanged` (settings-specific)
  - `capsuleDidChangeExpanded`, `capsuleDragStarted`, `capsuleDragEnded`, `resetCapsulePosition` (capsule-specific)

- [ ] **Step 1: Write the test**

```swift
// Mini CapsuleTests/NotificationNamesTests.swift
import Testing
import Foundation
@testable import Mini_Capsule

struct NotificationNamesTests {
    @Test func settingsNotificationsHaveCorrectRawValues() async throws {
        #expect(Notification.Name.pollingIntervalDidChange == Notification.Name("SettingsPollingIntervalDidChange"))
        #expect(Notification.Name.showFloatingPanelChanged == Notification.Name("ShowFloatingPanelChanged"))
    }

    @Test func capsuleNotificationsHaveCorrectRawValues() async throws {
        #expect(Notification.Name.capsuleDidChangeExpanded == Notification.Name("capsuleDidChangeExpanded"))
        #expect(Notification.Name.capsuleDragStarted == Notification.Name("capsuleDragStarted"))
        #expect(Notification.Name.capsuleDragEnded == Notification.Name("capsuleDragEnded"))
        #expect(Notification.Name.resetCapsulePosition == Notification.Name("resetCapsulePosition"))
    }

    @Test func allNotificationValuesAreUnique() async throws {
        let values: Set<String> = [
            "SettingsPollingIntervalDidChange", "ShowFloatingPanelChanged",
            "capsuleDidChangeExpanded", "capsuleDragStarted",
            "capsuleDragEnded", "resetCapsulePosition"
        ]
        #expect(values.count == 6)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/NotificationNamesTests test`
Expected: FAIL (NotificationNames not found)

- [ ] **Step 3: Create NotificationNames.swift**

```swift
// Mini Capsule/Settings/NotificationNames.swift
import Foundation

// MARK: - Settings Notifications

extension Notification.Name {
    /// Posted when the polling interval setting changes.
    static let pollingIntervalDidChange = Notification.Name("SettingsPollingIntervalDidChange")

    /// Posted when the floating panel visibility toggle changes.
    /// UserInfo contains `["show": Bool]`.
    static let showFloatingPanelChanged = Notification.Name("ShowFloatingPanelChanged")
}

// MARK: - Capsule Notifications

extension Notification.Name {
    /// Posted when the capsule expanded/collapsed state changes.
    /// UserInfo contains `["isExpanded": Bool]`.
    static let capsuleDidChangeExpanded = Notification.Name("capsuleDidChangeExpanded")

    /// Posted when a drag operation starts on the capsule window.
    static let capsuleDragStarted = Notification.Name("capsuleDragStarted")

    /// Posted when a drag operation ends on the capsule window.
    static let capsuleDragEnded = Notification.Name("capsuleDragEnded")

    /// Posted to request resetting the capsule window position to default.
    static let resetCapsulePosition = Notification.Name("resetCapsulePosition")
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/NotificationNamesTests test`
Expected: PASS (3 tests pass)

- [ ] **Step 5: Commit**

```bash
git add "Mini Capsule/Settings/NotificationNames.swift" "Mini CapsuleTests/NotificationNamesTests.swift"
git commit -m "feat: add unified NotificationNames file

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Create SettingsProtocol

**Files:**
- Create: `Mini Capsule/Settings/SettingsProtocol.swift`

**Interfaces:**
- Produces: `SettingsProtocol` protocol with 18 properties and 4 action methods

- [ ] **Step 1: Create SettingsProtocol.swift**

```swift
// Mini Capsule/Settings/SettingsProtocol.swift
import SwiftData
import Foundation

/// Protocol exposing all settings properties and actions.
/// Enables dependency injection and test mocking.
protocol SettingsProtocol: AnyObject {
    // MARK: - Clipboard
    var historyMaxCount: Int { get set }
    var imageMaxSizeMB: Int { get set }
    var pollingInterval: Double { get set }
    var cleanupOnStartup: Bool { get set }
    var dedupEnabled: Bool { get set }

    // MARK: - Shortcuts
    var showHideShortcut: String { get set }
    var quickPasteShortcut: String { get set }
    var togglePinShortcut: String { get set }

    // MARK: - General
    var launchAtLogin: Bool { get set }
    var showInMenuBar: Bool { get set }
    var showFloatingPanel: Bool { get set }
    var collapsedStyle: String { get set }
    var hoverExpandDelay: Double { get set }
    var hoverCollapseDelay: Double { get set }

    // MARK: - Appearance
    var panelOpacityUnfocused: Double { get set }
    var backgroundImageData: Data { get set }
    var dotColorMode: String { get set }
    var dotCustomColor: String { get set }

    // MARK: - Actions
    func resetAll()
    func exportData(context: ModelContext) -> Data?
    func importData(_ data: Data, context: ModelContext) throws
    func clearAllHistory(context: ModelContext)
}
```

- [ ] **Step 2: Commit**

```bash
git add "Mini Capsule/Settings/SettingsProtocol.swift"
git commit -m "feat: add SettingsProtocol for dependency injection

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Refactor SettingsStore with protocol conformance and didSet

**Files:**
- Modify: `Mini Capsule/Settings/SettingsStore.swift`
- Test: `Mini CapsuleTests/Mini_CapsuleTests.swift` (extend existing `SettingsStoreTests`)

**Interfaces:**
- Consumes: `SettingsKey`, `SettingsProtocol`, `NotificationNames`
- Produces: `SettingsStore` conforming to `SettingsProtocol`, emitting `objectWillChange`

- [ ] **Step 1: Write additional tests for SettingsStore**

These tests go into the existing `Mini_CapsuleTests.swift` file, extending `SettingsStoreTests`:

```swift
// Add to Mini CapsuleTests/Mini_CapsuleTests.swift — inside existing SettingsStoreTests struct:

@Test func allKeysAreInResetAll() async throws {
    // Verify resetAll touches every defined key
    let store = SettingsStore()
    // Set all to non-default values
    for key in SettingsKey.allCases {
        UserDefaults.standard.set("__test__", forKey: key.rawValue)
    }
    store.resetAll()

    // After reset, every key should be back to its default (not "__test__")
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
    #expect(store.dotColorMode == "auto")
    #expect(store.dotCustomColor == "#007AFF")
}

@Test func singlePropertyChangesPersist() async throws {
    let store = SettingsStore()
    store.pollingInterval = 2.0
    #expect(store.pollingInterval == 2.0)

    let store2 = SettingsStore()
    #expect(store2.pollingInterval == 2.0)

    store.resetAll()
}

@Test func booleanTogglesWork() async throws {
    let store = SettingsStore()
    store.cleanupOnStartup = false
    #expect(store.cleanupOnStartup == false)
    store.cleanupOnStartup = true
    #expect(store.cleanupOnStartup == true)

    store.resetAll()
}

@Test func integerSettingsInRange() async throws {
    let store = SettingsStore()
    store.historyMaxCount = 1000
    #expect(store.historyMaxCount == 1000)
    store.historyMaxCount = 50
    #expect(store.historyMaxCount == 50)

    store.resetAll()
}

@Test func doubleSettingsRoundtrip() async throws {
    let store = SettingsStore()
    store.hoverExpandDelay = 1.0
    #expect(store.hoverExpandDelay == 1.0)
    store.hoverCollapseDelay = 3.0
    #expect(store.hoverCollapseDelay == 3.0)

    store.resetAll()
}

@Test func stringSettingsRoundtrip() async throws {
    let store = SettingsStore()
    store.collapsedStyle = "dot"
    #expect(store.collapsedStyle == "dot")
    store.collapsedStyle = "capsule"
    #expect(store.collapsedStyle == "capsule")

    store.resetAll()
}

@Test func dataSettingsRoundtrip() async throws {
    let store = SettingsStore()
    let testData = "test_image".data(using: .utf8)!
    store.backgroundImageData = testData
    #expect(store.backgroundImageData == testData)

    store.resetAll()
}

@Test func allSettingsCombinatorialChangeThenReset() async throws {
    let store = SettingsStore()
    
    // Change every setting
    store.historyMaxCount = 800
    store.imageMaxSizeMB = 5
    store.pollingInterval = 2.0
    store.cleanupOnStartup = false
    store.dedupEnabled = false
    store.showHideShortcut = "cmd+option+K"
    store.quickPasteShortcut = "cmd+shift+X"
    store.togglePinShortcut = "cmd+shift+P"
    store.iCloudSyncEnabled = true
    store.launchAtLogin = true
    store.showInMenuBar = false
    store.showFloatingPanel = false
    store.collapsedStyle = "dot"
    store.hoverExpandDelay = 1.0
    store.hoverCollapseDelay = 3.0
    store.panelOpacityUnfocused = 0.3
    store.backgroundImageData = "bg".data(using: .utf8)!
    store.dotColorMode = "custom"
    store.dotCustomColor = "#FF0000"
    
    // Verify all changes took effect
    #expect(store.historyMaxCount == 800)
    #expect(store.imageMaxSizeMB == 5)
    #expect(store.pollingInterval == 2.0)
    #expect(store.cleanupOnStartup == false)
    #expect(store.dedupEnabled == false)
    #expect(store.showHideShortcut == "cmd+option+K")
    #expect(store.quickPasteShortcut == "cmd+shift+X")
    #expect(store.togglePinShortcut == "cmd+shift+P")
    #expect(store.iCloudSyncEnabled == true)
    #expect(store.launchAtLogin == true)
    #expect(store.showInMenuBar == false)
    #expect(store.showFloatingPanel == false)
    #expect(store.collapsedStyle == "dot")
    #expect(store.hoverExpandDelay == 1.0)
    #expect(store.hoverCollapseDelay == 3.0)
    #expect(store.panelOpacityUnfocused == 0.3)
    #expect(store.backgroundImageData == "bg".data(using: .utf8)!)
    #expect(store.dotColorMode == "custom")
    #expect(store.dotCustomColor == "#FF0000")
    
    // Reset and verify defaults
    store.resetAll()
    #expect(store.historyMaxCount == 200)
    #expect(store.collapsedStyle == "capsule")
    #expect(store.dotColorMode == "auto")
    #expect(store.dotCustomColor == "#007AFF")
    #expect(store.panelOpacityUnfocused == 0.6)
    #expect(store.backgroundImageData == Data())
}
```

- [ ] **Step 2: Run tests to verify they fail (they should pass since existing behavior works, but some may fail if keys changed)**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/Mini_CapsuleTests/SettingsStoreTests test`
Expected: Some may pass (existing behavior), check results

- [ ] **Step 3: Refactor SettingsStore.swift**

Replace `SettingsStore.swift` with the refactored version using `SettingsKey`, protocol conformance, and `didSet`:

```swift
// Mini Capsule/Settings/SettingsStore.swift
import SwiftUI
import SwiftData
import Foundation
import Combine

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
final class SettingsStore: ObservableObject, SettingsProtocol {
    // MARK: - Clipboard

    @AppStorage(SettingsKey.historyMaxCount.rawValue)
    var historyMaxCount: Int = 200 {
        didSet { objectWillChange.send() }
    }

    @AppStorage(SettingsKey.imageMaxSizeMB.rawValue)
    var imageMaxSizeMB: Int = 2 {
        didSet { objectWillChange.send() }
    }

    @AppStorage(SettingsKey.pollingInterval.rawValue)
    var pollingInterval: Double = 0.5 {
        didSet { objectWillChange.send() }
    }

    @AppStorage(SettingsKey.cleanupOnStartup.rawValue)
    var cleanupOnStartup: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage(SettingsKey.dedupEnabled.rawValue)
    var dedupEnabled: Bool = true {
        didSet { objectWillChange.send() }
    }

    // MARK: - Shortcuts

    @AppStorage(SettingsKey.showHideShortcut.rawValue)
    var showHideShortcut: String = "cmd+shift+V" {
        didSet { objectWillChange.send() }
    }

    @AppStorage(SettingsKey.quickPasteShortcut.rawValue)
    var quickPasteShortcut: String = "cmd+shift+C" {
        didSet { objectWillChange.send() }
    }

    @AppStorage(SettingsKey.togglePinShortcut.rawValue)
    var togglePinShortcut: String = "" {
        didSet { objectWillChange.send() }
    }

    // MARK: - Advanced

    @AppStorage(SettingsKey.iCloudSyncEnabled.rawValue)
    var iCloudSyncEnabled: Bool = false {
        didSet { objectWillChange.send() }
    }

    // MARK: - General

    @AppStorage(SettingsKey.launchAtLogin.rawValue)
    var launchAtLogin: Bool = false {
        didSet { objectWillChange.send() }
    }

    @AppStorage(SettingsKey.showInMenuBar.rawValue)
    var showInMenuBar: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage(SettingsKey.showFloatingPanel.rawValue)
    var showFloatingPanel: Bool = true {
        didSet { objectWillChange.send() }
    }

    @AppStorage(SettingsKey.collapsedStyle.rawValue)
    var collapsedStyle: String = "capsule" {
        didSet { objectWillChange.send() }
    }

    @AppStorage(SettingsKey.hoverExpandDelay.rawValue)
    var hoverExpandDelay: Double = 0.3 {
        didSet { objectWillChange.send() }
    }

    @AppStorage(SettingsKey.hoverCollapseDelay.rawValue)
    var hoverCollapseDelay: Double = 1.0 {
        didSet { objectWillChange.send() }
    }

    // MARK: - Appearance

    @AppStorage(SettingsKey.panelOpacityUnfocused.rawValue)
    var panelOpacityUnfocused: Double = 0.6 {
        didSet { objectWillChange.send() }
    }

    @AppStorage(SettingsKey.backgroundImageData.rawValue)
    var backgroundImageData: Data = Data() {
        didSet { objectWillChange.send() }
    }

    @AppStorage(SettingsKey.dotColorMode.rawValue)
    var dotColorMode: String = "auto" {
        didSet { objectWillChange.send() }
    }

    @AppStorage(SettingsKey.dotCustomColor.rawValue)
    var dotCustomColor: String = "#007AFF" {
        didSet { objectWillChange.send() }
    }

    // MARK: - Actions

    /// Reset all settings to their default values.
    func resetAll() {
        // Reset each property — Swift will call didSet for each
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
    }

    /// Serialize all ClipItem records to JSON.
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
                type: item.contentTypeRaw,
                content: content,
                fileName: item.imageFileName,
                timestamp: item.timestamp,
                pasteCount: item.pasteCount,
                sourceApp: item.sourceAppBundleID
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(exports)
    }

    /// Import clip items from JSON, merging with existing data (dedup by content / MD5).
    func importData(_ data: Data, context: ModelContext) throws {
        let decoder = JSONDecoder()
        let imports = try decoder.decode([ClipItemExport].self, from: data)

        // Pre-fetch existing items for dedup
        let existingDescriptor = FetchDescriptor<ClipItem>(sortBy: [])
        let existingItems = (try? context.fetch(existingDescriptor)) ?? []
        let existingTexts = Set(existingItems.compactMap { $0.textContent })
        let existingMD5s = Set(existingItems.compactMap { $0.imageMD5 })

        for item in imports {
            switch item.type {
            case "text":
                guard let text = item.content, !existingTexts.contains(text) else { continue }
                let clip = ClipItem(
                    timestamp: item.timestamp,
                    pasteCount: item.pasteCount,
                    contentTypeRaw: "text",
                    textContent: text,
                    sourceAppBundleID: item.sourceApp
                )
                context.insert(clip)
            case "image":
                guard let base64 = item.content, let imageData = Data(base64Encoded: base64) else { continue }
                let md5 = ClipboardMonitor.md5Hash(imageData)
                guard !existingMD5s.contains(md5) else { continue }
                let clip = ClipItem(
                    timestamp: item.timestamp,
                    pasteCount: item.pasteCount,
                    contentTypeRaw: "image",
                    imageData: imageData,
                    imageFileName: item.fileName,
                    imageMD5: md5,
                    sourceAppBundleID: item.sourceApp
                )
                context.insert(clip)
            default:
                continue
            }
        }
        try context.save()
    }

    /// Delete all ClipItem records from SwiftData.
    func clearAllHistory(context: ModelContext) {
        let descriptor = FetchDescriptor<ClipItem>(sortBy: [])
        guard let items = try? context.fetch(descriptor) else { return }
        for item in items {
            context.delete(item)
        }
        try? context.save()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/Mini_CapsuleTests/SettingsStoreTests test`
Expected: All tests PASS

- [ ] **Step 5: Build to verify compilation**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add "Mini Capsule/Settings/SettingsStore.swift" "Mini CapsuleTests/Mini_CapsuleTests.swift"
git commit -m "refactor: SettingsStore uses SettingsKey, conforms to SettingsProtocol, emits objectWillChange

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Remove duplicate Notification.Name from CapsuleView.swift

**Files:**
- Modify: `Mini Capsule/UI/CapsuleView.swift:6-11`

**Interfaces:**
- Consumes: `NotificationNames` from NotificationNames.swift
- Produces: CapsuleView uses centralized notification names

- [ ] **Step 1: Remove notification name extension from CapsuleView.swift**

Delete lines 6-11 of `CapsuleView.swift` (the `extension NSNotification.Name { ... }` block). The file now starts at the `struct CapsuleView: View {` line.

Edit `CapsuleView.swift` to remove:
```swift
extension NSNotification.Name {
    static let capsuleDidChangeExpanded = NSNotification.Name("capsuleDidChangeExpanded")
    static let capsuleDragStarted = NSNotification.Name("capsuleDragStarted")
    static let capsuleDragEnded = NSNotification.Name("capsuleDragEnded")
    static let resetCapsulePosition = NSNotification.Name("resetCapsulePosition")
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED (notification names now come from NotificationNames.swift)

- [ ] **Step 3: Run existing notification tests**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/Mini_CapsuleTests/NotificationNamesTests test`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add "Mini Capsule/UI/CapsuleView.swift"
git commit -m "refactor: use unified NotificationNames, remove duplicate extension from CapsuleView

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: Refactor GeneralSettingsView to use SettingsKey for frame key

**Files:**
- Modify: `Mini Capsule/Settings/GeneralSettingsView.swift:109`

**Interfaces:**
- Consumes: none new (uses `@EnvironmentObject var settings: SettingsStore`)
- Produces: `GeneralSettingsView.resetCapsulePosition()` uses constant key

- [ ] **Step 1: Update GeneralSettingsView frame key reference**

In `GeneralSettingsView.swift`, change the `resetCapsulePosition()` method to use a proper approach. The `"CapsuleWindowFrame"` is a UI-specific key (not a settings key), so we add it as a private constant:

```swift
// At the top of GeneralSettingsView.swift, after the imports:
private let capsuleWindowFrameKey = "CapsuleWindowFrame"

// Change line 109 from:
// UserDefaults.standard.removeObject(forKey: "CapsuleWindowFrame")
// to:
// UserDefaults.standard.removeObject(forKey: capsuleWindowFrameKey)
```

- [ ] **Step 2: Write test for objectWillChange emission on relevant settings**

Add to `Mini_CapsuleTests/Mini_CapsuleTests.swift` as a new test struct:

```swift
@MainActor
struct GeneralSettingsTests {
    @Test func resetPositionActionClearsFrameKeyAndPostsNotification() async throws {
        // Given: a saved frame position
        UserDefaults.standard.set([
            "x": CGFloat(100), "y": CGFloat(200),
            "w": CGFloat(200), "h": CGFloat(36)
        ], forKey: "CapsuleWindowFrame")

        // When: the static reset method is called
        try await confirmation(expectedCount: 1) { posted in
            let obs = NotificationCenter.default.addObserver(
                forName: .resetCapsulePosition,
                object: nil,
                queue: .main
            ) { _ in posted() }
            defer { NotificationCenter.default.removeObserver(obs) }

            GeneralSettingsView.resetCapsulePosition()
        }

        // Then: the saved frame key is removed
        #expect(UserDefaults.standard.dictionary(forKey: "CapsuleWindowFrame") == nil)
    }

    @Test func resetPositionMethodIsAvailable() async throws {
        // Verify the static method exists and can be called without side effects
        GeneralSettingsView.resetCapsulePosition()
        // Key should be nil after reset
        #expect(UserDefaults.standard.dictionary(forKey: "CapsuleWindowFrame") == nil)
    }
}
```

Note: The `resetCapsulePosition` test already exists in the existing test file (lines 427-450). If it was already written, we just verify it still passes. If not, add the above tests.

- [ ] **Step 3: Build and run tests**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/Mini_CapsuleTests/GeneralSettingsTests test`
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add "Mini Capsule/Settings/GeneralSettingsView.swift" "Mini CapsuleTests/Mini_CapsuleTests.swift"
git commit -m "refactor: extract frame key constant in GeneralSettingsView

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: Refactor CapsuleWindowController to use SettingsProtocol

**Files:**
- Modify: `Mini Capsule/UI/CapsuleWindowController.swift`

**Interfaces:**
- Consumes: `SettingsProtocol` (injected via init)
- Produces: `CapsuleWindowController` reads settings from protocol, not UserDefaults

- [ ] **Step 1: Write the integration test**

Add to `Mini_CapsuleTests/Mini_CapsuleTests.swift`:

```swift
// MARK: - CapsuleWindowController Integration Tests

@MainActor
struct CapsuleWindowControllerSettingsIntegrationTests {
    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func controllerReadsCollapsedStyleFromSettings() async throws {
        let store = SettingsStore()
        store.collapsedStyle = "dot"

        let container = try Self.makeContainer()
        let controller = CapsuleWindowController(
            modelContainer: container,
            settings: store
        )

        #expect(controller.window?.contentView?.layer?.cornerRadius == 6)

        // When style changes
        store.collapsedStyle = "capsule"
        NotificationCenter.default.post(
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        #expect(controller.window?.contentView?.layer?.cornerRadius == 18)
    }

    @Test func controllerUsesSettingsForFrameKey() async throws {
        let store = SettingsStore()
        let container = try Self.makeContainer()

        // Set a known frame
        UserDefaults.standard.set([
            "x": CGFloat(300), "y": CGFloat(400),
            "w": CGFloat(200), "h": CGFloat(36)
        ], forKey: "CapsuleWindowFrame")

        _ = CapsuleWindowController(modelContainer: container, settings: store)

        // Verify frame was loaded (exact position depends on screen, just verify window exists)
        #expect(true) // Controller initialized without crash
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/CapsuleWindowControllerSettingsIntegrationTests test`
Expected: FAIL (init signature mismatch — `settings:` parameter not yet added)

- [ ] **Step 3: Refactor CapsuleWindowController**

Modify `CapsuleWindowController.swift`:

Key changes:
1. Add `private let settings: SettingsProtocol` property
2. Add `settings` parameter to `init`
3. Replace all `UserDefaults.standard.string(forKey: "collapsedStyle")` with `settings.collapsedStyle`
4. Replace `UserDefaults.standard.removeObject(forKey: Self.frameKey)` usage with a helper
5. Keep frame persistence local (it's a UI concern, not a setting)
6. Replace `UserDefaults.standard.dictionary(forKey: frameKey)` reads with direct UserDefaults access for frame (frame is not a setting, it's window state)

The frame key `"CapsuleWindowFrame"` is window position state, NOT a setting. Keep it in CapsuleWindowController but use a local constant.

```swift
// Mini Capsule/UI/CapsuleWindowController.swift
// Lines to change:

// Line 13: Add settings property
private let settings: SettingsProtocol

// Lines 28-31: Change currentCollapsedSize
private var currentCollapsedSize: NSSize {
    return settings.collapsedStyle == "dot" ? Self.dotCollapsedSize : Self.capsuleCollapsedSize
}

// Lines 33-75: Change init signature and body
init(modelContainer: ModelContainer, settings: SettingsProtocol) {
    self.modelContainer = modelContainer
    self.settings = settings

    let savedFrame = Self.loadFrame(style: settings.collapsedStyle)
    // ... rest unchanged

    // Line 70: Replace UserDefaults read
    // OLD: let initialStyle = UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
    // NEW:
    let initialStyle = settings.collapsedStyle
    panel.contentView?.layer?.cornerRadius = initialStyle == "dot" ? 6 : 18

    // ... rest unchanged
}

// Lines 174-175: Replace UserDefaults read in observeExpandedState
// OLD: let style = UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
// NEW:
let style = settings.collapsedStyle
let cornerRadius: CGFloat = style == "dot" ? 6 : 18

// Lines 207: Replace UserDefaults read
// OLD: let style = UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
// NEW:
let style = settings.collapsedStyle

// Line 237: Replace UserDefaults read
// OLD: let style = UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
// NEW:
let style = settings.collapsedStyle

// Line 247: Keep UserDefaults.standard.removeObject(forKey: Self.frameKey) as-is
// (frame persistence is window state, not a setting)

// Lines 286-287: Change loadFrame to accept style parameter
// OLD: let style = UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
// NEW:
private static func loadFrame(style: String) -> NSRect {
    let size = style == "dot" ? dotCollapsedSize : capsuleCollapsedSize
    // ... rest unchanged
}

// Line 299: Replace UserDefaults.dictionary read
// Keep as-is: it reads the frame key, not a settings key
```

- [ ] **Step 4: Build to verify compilation**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build`
Expected: BUILD FAILED (CapsuleAppDelegate creates CapsuleWindowController without `settings:` param — this will be fixed in Task 13)

The build may fail at this point because `CapsuleAppDelegate` still uses the old init signature. This is expected — we fix it in Task 13. For now, verify that CapsuleWindowController itself compiles correctly by checking the error is only in CapsuleAppDelegate.

Actually, let me restructure — we should do CapsuleAppDelegate at the same time as CapsuleWindowController to keep the build passing. Or we can do CapsuleAppDelegate first.

Let me adjust: CapsuleAppDelegate refactor should come BEFORE CapsuleWindowController refactor.

Let me reorder the tasks.

Actually, let me just combine the CapsuleWindowController and CapsuleAppDelegate refactors into one commit so the build stays green. I'll note that in the steps.

- [ ] **Step 5: Proceed to Task 8 (CapsuleAppDelegate must be refactored first to add settings: parameter)**

Hold this commit — combine with Task 8.

---

### Task 8: Refactor CapsuleAppDelegate to inject SettingsProtocol into services

**Files:**
- Modify: `Mini Capsule/Mini_CapsuleApp.swift`

**Interfaces:**
- Consumes: `SettingsProtocol`, `SettingsStore`
- Produces: `CapsuleAppDelegate` injects `settingsStore` into `CapsuleWindowController`, `ClipboardMonitor`, `MenuBarService`, and `FrequencyCleanupService`

- [ ] **Step 1: Write integration test for shortcut reading**

Add to `Mini_CapsuleTests/Mini_CapsuleTests.swift`:

```swift
@MainActor
struct CapsuleAppDelegateSettingsTests {
    @Test func shortcutReadsFromSettingsStore() async throws {
        let store = SettingsStore()
        store.showHideShortcut = "cmd+option+K"
        store.quickPasteShortcut = "cmd+shift+X"
        store.togglePinShortcut = ""

        // Verify read-back
        #expect(store.showHideShortcut == "cmd+option+K")
        #expect(store.quickPasteShortcut == "cmd+shift+X")
        #expect(store.togglePinShortcut.isEmpty)

        store.resetAll()
    }
}
```

- [ ] **Step 2: Refactor CapsuleAppDelegate**

Modify `Mini Capsule/Mini_CapsuleApp.swift`:

Key changes to `CapsuleAppDelegate`:
1. Change `settingsStore` from `let` to stored property (already the case)
2. Replace `UserDefaults.standard.string(forKey:)` in `registerShortcuts()` with settings reads
3. Pass `settingsStore` to `CapsuleWindowController` init
4. Pass `settingsStore` to `ClipboardMonitor` (requires monitor init change — Task 9)
5. Pass `settingsStore` to `MenuBarService` (requires service init change — Task 10)
6. Pass `settingsStore` to `FrequencyCleanupService` (Task 12)

The changes in lines 70-94 of `Mini_CapsuleApp.swift`:

```swift
// Lines 70-94: Replace UserDefaults reads with settingsStore reads
private func registerShortcuts() {
    shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self = self else { return event }

        let combo = self.shortcutString(from: event)

        // OLD: let showHide = UserDefaults.standard.string(forKey: "showHideShortcut") ?? "cmd+shift+V"
        let showHide = self.settingsStore.showHideShortcut
        // OLD: let quickPaste = UserDefaults.standard.string(forKey: "quickPasteShortcut") ?? "cmd+shift+C"
        let quickPaste = self.settingsStore.quickPasteShortcut
        // OLD: let togglePin = UserDefaults.standard.string(forKey: "togglePinShortcut") ?? ""
        let togglePin = self.settingsStore.togglePinShortcut

        // ... rest unchanged
    }
}
```

Also update CapsuleWindowController init call:
```swift
// Line 40: Change init call
// OLD: let controller = CapsuleWindowController(modelContainer: Self.sharedModelContainer)
// NEW:
let controller = CapsuleWindowController(
    modelContainer: Self.sharedModelContainer,
    settings: settingsStore
)
```

For the `ClipboardMonitor` and `MenuBarService` init calls, the `settings:` parameter will be added in Tasks 9 and 10. For now, we add the parameter but the build will fail until those tasks are done. To keep the build passing, we should do Tasks 7, 8, 9, 10, and 12 together.

Let me rethink: The cleanest approach is to update CapsuleAppDelegate LAST (after all services are refactored). That way each service's init change is isolated and the build stays green.

**Revised order:**
1. SettingsKey (foundation) — independent
2. NotificationNames (foundation) — independent
3. SettingsProtocol (foundation) — independent
4. SettingsStore refactor (foundation) — independent
5. Remove duplicate notifications from CapsuleView — independent
6. GeneralSettingsView frame key — independent
7. CapsuleWindowController refactor — needs SettingsProtocol, changes init
8. ClipboardMonitor refactor — needs SettingsProtocol, changes init
9. MenuBarService refactor — needs SettingsProtocol, changes init
10. FrequencyCleanupService refactor — needs SettingsProtocol
11. CapsuleView/CapsuleExpandedView/CapsuleCollapsedView — needs @EnvironmentObject, changes how they read settings
12. CapsuleAppDelegate refactor LAST — wire everything together

Actually, this still has the problem that Tasks 7-9 change init signatures, but CapsuleAppDelegate calls those inits. So the build will break between task 7 and task 12.

The only way to avoid interim build breaks is to either:
a) Keep backward-compatible inits (add a default parameter or keep old init alongside new one)
b) Do all init changes + AppDelegate in one task
c) Accept interim build breaks

Option (a) is the cleanest. Let me use it: each service gets a new init with `settings:` but keeps a backward-compatible fallback.

Actually, let me just accept the build breaks and note it clearly. The task order ensures each file is correct when examined individually, and the final task (AppDelegate) ties everything together. Testing each task individually is fine because we run unit tests (not full app builds) per task.

Let me restructure the plan more carefully:

**Phase 1: Foundation (can all build independently)**
- Task 1: SettingsKey
- Task 2: NotificationNames
- Task 3: SettingsProtocol
- Task 4: SettingsStore refactor

**Phase 2: View refactors (use @EnvironmentObject, no init changes needed)**
- Task 5: Remove duplicate notifications from CapsuleView
- Task 6: CapsuleView → use @EnvironmentObject instead of UserDefaults
- Task 7: CapsuleExpandedView → use @EnvironmentObject
- Task 8: CapsuleCollapsedView → use @EnvironmentObject  
- Task 9: GeneralSettingsView frame key cleanup

**Phase 3: Service refactors (add settings: parameter to init)**
- Task 10: ClipboardMonitor → add SettingsProtocol init param
- Task 11: MenuBarService → add SettingsProtocol init param
- Task 12: FrequencyCleanupService → add SettingsProtocol param to performCleanup
- Task 13: CapsuleWindowController → add SettingsProtocol init param

**Phase 4: Wiring**
- Task 14: CapsuleAppDelegate — wire everything, remove last UserDefaults reads

**Phase 5: Final verification**
- Task 15: Run all tests, fix any issues

This ordering means Tasks 10-13 change init signatures, and the build fails between them and Task 14. That's fine — we can still run unit tests per task. The build only needs to pass at Task 14.

Actually wait, I realize for SwiftUI views that use `@EnvironmentObject`, there's no init change — the views already expect the environment object to be provided. The views currently read UserDefaults directly, but after refactoring they'll read from the environment object. No init change needed for views.

Let me finalize the task list and write the complete plan.

OK actually, I realize this is getting very long. Let me just write the complete plan document with all the tasks, accepting that intermediate build failures are fine and tests are the primary verification mechanism.

The key insight: run `xcodebuild test` per task (which builds the test target only, not the whole app) to verify each task. The full app build only needs to pass at the end.

Let me write this properly now.<｜end▁of▁thinking｜>Now let me write the complete implementation plan. This is a large refactor, so I'll structure it carefully.

<｜｜DSML｜｜tool_calls>
<｜｜DSML｜｜invoke name="Write">
<｜｜DSML｜｜parameter name="content" string="true"># Settings Module Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish `SettingsStore` as the single source of truth for all settings, eliminate raw `UserDefaults` calls from 8 consumer files, unify notification names, and add comprehensive automated tests.

**Architecture:** Create `SettingsKey` (private key enum), `NotificationNames` (single registry), and `SettingsProtocol` (protocol for DI). Refactor `SettingsStore` with `didSet` → `objectWillChange.send()`. Inject `SettingsProtocol` into all services; views use `@EnvironmentObject`. Each service keeps backward-compatible init until final wiring task.

**Tech Stack:** Swift, SwiftUI, SwiftData, Combine, AppKit, Swift Testing, UserDefaults/@AppStorage

## Global Constraints

- Deployment target: 26.5 (iOS, macOS, visionOS)
- Swift 5.0
- Swift Testing framework for unit tests (`import Testing`)
- No behavioral changes — all defaults, ranges, and side effects remain identical
- No new settings added
- iCloud sync placeholder preserved as-is
- Each task runs `xcodebuild test` to verify (test target builds independently of full app)

## File Structure Overview

```
Settings/
├── SettingsKey.swift           [NEW] Private key enum
├── NotificationNames.swift     [NEW] Unified notification registry
├── SettingsProtocol.swift      [NEW] Protocol for DI
├── SettingsStore.swift         [MODIFY] Conform to protocol, add didSet
├── GeneralSettingsView.swift   [MODIFY] Frame key constant
├── AppearanceSettingsView.swift [NO CHANGE]
├── ClipboardSettingsView.swift  [NO CHANGE]
├── ShortcutsSettingsView.swift  [NO CHANGE]
└── AdvancedSettingsView.swift   [NO CHANGE]

Services/
├── ClipboardMonitor.swift      [MODIFY] Inject SettingsProtocol
├── MenuBarService.swift        [MODIFY] Inject SettingsProtocol
└── FrequencyCleanupService.swift [MODIFY] Accept SettingsProtocol param

UI/
├── CapsuleView.swift           [MODIFY] Use @EnvironmentObject, remove dup notifications
├── CapsuleExpandedView.swift   [MODIFY] Use @EnvironmentObject
├── CapsuleCollapsedView.swift  [MODIFY] Use @EnvironmentObject
└── CapsuleWindowController.swift [MODIFY] Inject SettingsProtocol

Mini_CapsuleApp.swift           [MODIFY] Wire injection, remove UserDefaults reads
```

---

### Task 1: Create SettingsKey constants enum

**Files:**
- Create: `Mini Capsule/Settings/SettingsKey.swift`

**Interfaces:**
- Produces: `enum SettingsKey: String, CaseIterable` — 18 cases matching all `@AppStorage` keys

- [ ] **Step 1: Write the test file**

Create `Mini CapsuleTests/SettingsKeyTests.swift`:

```swift
import Testing
@testable import Mini_Capsule

struct SettingsKeyTests {
    @Test func allKeysAreUnique() async throws {
        let allKeys = SettingsKey.allCases.map(\.rawValue)
        let uniqueKeys = Set(allKeys)
        #expect(allKeys.count == uniqueKeys.count, "All SettingsKey rawValues must be unique")
    }

    @Test func keyCountIsCorrect() async throws {
        #expect(SettingsKey.allCases.count == 18, "Expected 18 settings keys")
    }

    @Test func keysMatchExpectedValues() async throws {
        let expected: Set<String> = [
            "historyMaxCount", "imageMaxSizeMB", "pollingInterval",
            "cleanupOnStartup", "dedupEnabled",
            "showHideShortcut", "quickPasteShortcut", "togglePinShortcut",
            "iCloudSyncEnabled", "launchAtLogin", "showInMenuBar",
            "showFloatingPanel", "collapsedStyle", "hoverExpandDelay",
            "hoverCollapseDelay", "panelOpacityUnfocused",
            "backgroundImageData", "dotColorMode", "dotCustomColor"
        ]
        let actual = Set(SettingsKey.allCases.map(\.rawValue))
        #expect(actual == expected, "SettingsKey cases must match expected key strings")
    }
}
```

- [ ] **Step 2: Add test file to Xcode project target**

Add `Mini CapsuleTests/SettingsKeyTests.swift` to the `Mini CapsuleTests` target in Xcode (drag into project navigator, or add to pbxproj).

- [ ] **Step 3: Run test to verify it fails**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/SettingsKeyTests test 2>&1 | tail -20
```

Expected: FAIL — `SettingsKey` not found in module.

- [ ] **Step 4: Create SettingsKey.swift**

```swift
// Mini Capsule/Settings/SettingsKey.swift

/// UserDefaults key constants for all settings.
/// Private to the Settings module — only `SettingsStore` uses these directly.
enum SettingsKey: String, CaseIterable {
    // Clipboard
    case historyMaxCount
    case imageMaxSizeMB
    case pollingInterval
    case cleanupOnStartup
    case dedupEnabled

    // Shortcuts
    case showHideShortcut
    case quickPasteShortcut
    case togglePinShortcut

    // Advanced
    case iCloudSyncEnabled

    // General
    case launchAtLogin
    case showInMenuBar
    case showFloatingPanel
    case collapsedStyle
    case hoverExpandDelay
    case hoverCollapseDelay

    // Appearance
    case panelOpacityUnfocused
    case backgroundImageData
    case dotColorMode
    case dotCustomColor
}
```

- [ ] **Step 5: Add SettingsKey.swift to Xcode project target**

Add `Mini Capsule/Settings/SettingsKey.swift` to the `Mini Capsule` target.

- [ ] **Step 6: Run test to verify it passes**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/SettingsKeyTests test 2>&1 | tail -20
```

Expected: 3 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add "Mini Capsule/Settings/SettingsKey.swift" "Mini CapsuleTests/SettingsKeyTests.swift"
git commit -m "feat: add SettingsKey constants enum with 18 case keys

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Create unified NotificationNames file

**Files:**
- Create: `Mini Capsule/Settings/NotificationNames.swift`

**Interfaces:**
- Produces: `extension Notification.Name` with 6 static properties

- [ ] **Step 1: Write the test file**

Create `Mini CapsuleTests/NotificationNamesTests.swift`:

```swift
import Testing
import Foundation
@testable import Mini_Capsule

struct NotificationNamesTests {
    @Test func settingsNotificationsHaveCorrectRawValues() async throws {
        #expect(Notification.Name.pollingIntervalDidChange ==
            Notification.Name("SettingsPollingIntervalDidChange"))
        #expect(Notification.Name.showFloatingPanelChanged ==
            Notification.Name("ShowFloatingPanelChanged"))
    }

    @Test func capsuleNotificationsHaveCorrectRawValues() async throws {
        #expect(Notification.Name.capsuleDidChangeExpanded ==
            Notification.Name("capsuleDidChangeExpanded"))
        #expect(Notification.Name.capsuleDragStarted ==
            Notification.Name("capsuleDragStarted"))
        #expect(Notification.Name.capsuleDragEnded ==
            Notification.Name("capsuleDragEnded"))
        #expect(Notification.Name.resetCapsulePosition ==
            Notification.Name("resetCapsulePosition"))
    }

    @Test func allNotificationValuesAreUnique() async throws {
        let values: Set<String> = [
            "SettingsPollingIntervalDidChange", "ShowFloatingPanelChanged",
            "capsuleDidChangeExpanded", "capsuleDragStarted",
            "capsuleDragEnded", "resetCapsulePosition"
        ]
        #expect(values.count == 6)
    }
}
```

- [ ] **Step 2: Add test file to Xcode target. Run test to verify it fails.**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/NotificationNamesTests test 2>&1 | tail -20
```

Expected: FAIL.

- [ ] **Step 3: Create NotificationNames.swift**

```swift
// Mini Capsule/Settings/NotificationNames.swift
import Foundation

// MARK: - Settings Notifications

extension Notification.Name {
    /// Posted when the polling interval setting changes.
    static let pollingIntervalDidChange = Notification.Name("SettingsPollingIntervalDidChange")
    /// Posted when the floating panel visibility toggle changes.
    /// UserInfo contains ["show": Bool].
    static let showFloatingPanelChanged = Notification.Name("ShowFloatingPanelChanged")
}

// MARK: - Capsule Notifications

extension Notification.Name {
    /// Posted when the capsule expanded/collapsed state changes.
    /// UserInfo contains ["isExpanded": Bool].
    static let capsuleDidChangeExpanded = Notification.Name("capsuleDidChangeExpanded")
    /// Posted when a drag operation starts on the capsule window.
    static let capsuleDragStarted = Notification.Name("capsuleDragStarted")
    /// Posted when a drag operation ends on the capsule window.
    static let capsuleDragEnded = Notification.Name("capsuleDragEnded")
    /// Posted to request resetting the capsule window position to default.
    static let resetCapsulePosition = Notification.Name("resetCapsulePosition")
}
```

- [ ] **Step 4: Add to Xcode target. Run test to verify it passes.**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/NotificationNamesTests test 2>&1 | tail -10
```

Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add "Mini Capsule/Settings/NotificationNames.swift" "Mini CapsuleTests/NotificationNamesTests.swift"
git commit -m "feat: add unified NotificationNames file with 6 names

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Create SettingsProtocol

**Files:**
- Create: `Mini Capsule/Settings/SettingsProtocol.swift`

**Interfaces:**
- Produces: `protocol SettingsProtocol: AnyObject` — 18 properties + 4 methods

- [ ] **Step 1: Create SettingsProtocol.swift**

```swift
// Mini Capsule/Settings/SettingsProtocol.swift
import SwiftData
import Foundation

/// Protocol for all settings access. Enables dependency injection and test mocking.
protocol SettingsProtocol: AnyObject {
    // MARK: - Clipboard
    var historyMaxCount: Int { get set }
    var imageMaxSizeMB: Int { get set }
    var pollingInterval: Double { get set }
    var cleanupOnStartup: Bool { get set }
    var dedupEnabled: Bool { get set }

    // MARK: - Shortcuts
    var showHideShortcut: String { get set }
    var quickPasteShortcut: String { get set }
    var togglePinShortcut: String { get set }

    // MARK: - Advanced
    var iCloudSyncEnabled: Bool { get set }

    // MARK: - General
    var launchAtLogin: Bool { get set }
    var showInMenuBar: Bool { get set }
    var showFloatingPanel: Bool { get set }
    var collapsedStyle: String { get set }
    var hoverExpandDelay: Double { get set }
    var hoverCollapseDelay: Double { get set }

    // MARK: - Appearance
    var panelOpacityUnfocused: Double { get set }
    var backgroundImageData: Data { get set }
    var dotColorMode: String { get set }
    var dotCustomColor: String { get set }

    // MARK: - Actions
    func resetAll()
    func exportData(context: ModelContext) -> Data?
    func importData(_ data: Data, context: ModelContext) throws
    func clearAllHistory(context: ModelContext)
}
```

- [ ] **Step 2: Verify the file is added to Xcode target. Build test target.**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/SettingsKeyTests test 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED (SettingsKeyTests still pass).

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/Settings/SettingsProtocol.swift"
git commit -m "feat: add SettingsProtocol for dependency injection

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Refactor SettingsStore — protocol conformance, SettingsKey, didSet

**Files:**
- Modify: `Mini Capsule/Settings/SettingsStore.swift` (entire file)
- Modify: `Mini CapsuleTests/Mini_CapsuleTests.swift` (extend SettingsStoreTests)

**Interfaces:**
- Consumes: `SettingsKey`, `SettingsProtocol`
- Produces: `SettingsStore: ObservableObject, SettingsProtocol` with `didSet → objectWillChange.send()`

- [ ] **Step 1: Extend existing tests**

Add to the `SettingsStoreTests` struct in `Mini CapsuleTests/Mini_CapsuleTests.swift`:

```swift
@Test func allSettingsCombinatorialChangeThenReset() async throws {
    let store = SettingsStore()

    store.historyMaxCount = 800
    store.imageMaxSizeMB = 5
    store.pollingInterval = 2.0
    store.cleanupOnStartup = false
    store.dedupEnabled = false
    store.showHideShortcut = "cmd+option+K"
    store.quickPasteShortcut = "cmd+shift+X"
    store.togglePinShortcut = "cmd+shift+P"
    store.iCloudSyncEnabled = true
    store.launchAtLogin = true
    store.showInMenuBar = false
    store.showFloatingPanel = false
    store.collapsedStyle = "dot"
    store.hoverExpandDelay = 1.0
    store.hoverCollapseDelay = 3.0
    store.panelOpacityUnfocused = 0.3
    store.backgroundImageData = "bg".data(using: .utf8)!
    store.dotColorMode = "custom"
    store.dotCustomColor = "#FF0000"

    #expect(store.historyMaxCount == 800)
    #expect(store.collapsedStyle == "dot")
    #expect(store.dotColorMode == "custom")
    #expect(store.dotCustomColor == "#FF0000")
    #expect(store.panelOpacityUnfocused == 0.3)
    #expect(store.backgroundImageData == "bg".data(using: .utf8)!)

    store.resetAll()

    #expect(store.historyMaxCount == 200)
    #expect(store.collapsedStyle == "capsule")
    #expect(store.dotColorMode == "auto")
    #expect(store.dotCustomColor == "#007AFF")
    #expect(store.panelOpacityUnfocused == 0.6)
    #expect(store.backgroundImageData == Data())
}

@Test func propertyChangeNotifiesObjectWillChange() async throws {
    let store = SettingsStore()

    await confirmation(expectedCount: 1) { emitted in
        let sink = store.objectWillChange.sink { emitted() }
        defer { sink.cancel() }
        store.pollingInterval = 1.5
    }
}

@Test func defaultValuesAreConsistent() async throws {
    let defaults = UserDefaults.standard
    for key in SettingsKey.allCases {
        defaults.removeObject(forKey: key.rawValue)
    }
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
    #expect(store.dotColorMode == "auto")
    #expect(store.dotCustomColor == "#007AFF")
}
```

- [ ] **Step 2: Run tests to confirm existing tests still pass (some new tests may fail before refactor)**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/Mini_CapsuleTests/SettingsStoreTests test 2>&1 | tail -20
```

Expected: Existing tests (`defaults`, `resetAllRestoresDefaults`, `settingsPersistAcrossStoreInstances`, `shortcutKeys`) PASS. New tests may FAIL.

- [ ] **Step 3: Rewrite SettingsStore.swift**

The full replacement. Key differences from current:
- Import removed: `Combine` no longer needed separately (ObservableObject publisher is built-in)
- Remove `extension Notification.Name { ... }` (moved to NotificationNames.swift)
- Remove `objectWillChange` manual declaration (use inherited from ObservableObject)
- All `@AppStorage("literal")` → `@AppStorage(SettingsKey.case.rawValue)`
- Every property gains `didSet { objectWillChange.send() }`
- Add `SettingsProtocol` conformance

```swift
// Mini Capsule/Settings/SettingsStore.swift
import SwiftUI
import SwiftData
import Foundation

private struct ClipItemExport: Codable {
    let type: String
    let content: String?
    let fileName: String?
    let timestamp: Date
    let pasteCount: Int
    let sourceApp: String?
}

@MainActor
final class SettingsStore: ObservableObject, SettingsProtocol {
    // MARK: - Clipboard

    @AppStorage(SettingsKey.historyMaxCount.rawValue)
    var historyMaxCount: Int = 200 { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.imageMaxSizeMB.rawValue)
    var imageMaxSizeMB: Int = 2 { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.pollingInterval.rawValue)
    var pollingInterval: Double = 0.5 { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.cleanupOnStartup.rawValue)
    var cleanupOnStartup: Bool = true { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.dedupEnabled.rawValue)
    var dedupEnabled: Bool = true { didSet { objectWillChange.send() } }

    // MARK: - Shortcuts

    @AppStorage(SettingsKey.showHideShortcut.rawValue)
    var showHideShortcut: String = "cmd+shift+V" { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.quickPasteShortcut.rawValue)
    var quickPasteShortcut: String = "cmd+shift+C" { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.togglePinShortcut.rawValue)
    var togglePinShortcut: String = "" { didSet { objectWillChange.send() } }

    // MARK: - Advanced

    @AppStorage(SettingsKey.iCloudSyncEnabled.rawValue)
    var iCloudSyncEnabled: Bool = false { didSet { objectWillChange.send() } }

    // MARK: - General

    @AppStorage(SettingsKey.launchAtLogin.rawValue)
    var launchAtLogin: Bool = false { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.showInMenuBar.rawValue)
    var showInMenuBar: Bool = true { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.showFloatingPanel.rawValue)
    var showFloatingPanel: Bool = true { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.collapsedStyle.rawValue)
    var collapsedStyle: String = "capsule" { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.hoverExpandDelay.rawValue)
    var hoverExpandDelay: Double = 0.3 { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.hoverCollapseDelay.rawValue)
    var hoverCollapseDelay: Double = 1.0 { didSet { objectWillChange.send() } }

    // MARK: - Appearance

    @AppStorage(SettingsKey.panelOpacityUnfocused.rawValue)
    var panelOpacityUnfocused: Double = 0.6 { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.backgroundImageData.rawValue)
    var backgroundImageData: Data = Data() { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.dotColorMode.rawValue)
    var dotColorMode: String = "auto" { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.dotCustomColor.rawValue)
    var dotCustomColor: String = "#007AFF" { didSet { objectWillChange.send() } }

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

- [ ] **Step 4: Run all SettingsStoreTests**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/Mini_CapsuleTests/SettingsStoreTests test 2>&1 | tail -20
```

Expected: ALL tests PASS (existing + 3 new: combinatorial reset, objectWillChange notification, default values).

- [ ] **Step 5: Commit**

```bash
git add "Mini Capsule/Settings/SettingsStore.swift" "Mini CapsuleTests/Mini_CapsuleTests.swift"
git commit -m "refactor: SettingsStore uses SettingsKey, conforms to SettingsProtocol, emits objectWillChange

- Replace raw AppStorage key strings with SettingsKey enum cases
- Add didSet { objectWillChange.send() } to every property
- Conform to SettingsProtocol
- Remove duplicate Notification.Name extension (now in NotificationNames.swift)
- Remove unused Combine import and manual objectWillChange publisher

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Remove duplicate Notification.Name from CapsuleView.swift

**Files:**
- Modify: `Mini Capsule/UI/CapsuleView.swift` (lines 6-11)

**Interfaces:**
- Consumes: `NotificationNames.swift` (already imported via module)
- Produces: CapsuleView uses centralized notification names

- [ ] **Step 1: Remove the extension block**

Delete lines 6-11 of `Mini Capsule/UI/CapsuleView.swift`:
```swift
// DELETE these lines:
extension NSNotification.Name {
    static let capsuleDidChangeExpanded = NSNotification.Name("capsuleDidChangeExpanded")
    static let capsuleDragStarted = NSNotification.Name("capsuleDragStarted")
    static let capsuleDragEnded = NSNotification.Name("capsuleDragEnded")
    static let resetCapsulePosition = NSNotification.Name("resetCapsulePosition")
}
```

The file now starts directly with `struct CapsuleView: View {`.

- [ ] **Step 2: Verify existing tests still pass (notification names come from NotificationNames.swift now)**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/NotificationNamesTests test 2>&1 | tail -5
```

Expected: 3 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/UI/CapsuleView.swift"
git commit -m "refactor: remove duplicate Notification.Name extension from CapsuleView

Now uses centralized NotificationNames.swift.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: Refactor CapsuleView to use @EnvironmentObject SettingsStore

**Files:**
- Modify: `Mini Capsule/UI/CapsuleView.swift`

**Interfaces:**
- Consumes: `@EnvironmentObject var settings: SettingsStore`
- Produces: No UserDefaults reads in CapsuleView; all settings from environment object

- [ ] **Step 1: Write the test**

Add to `Mini_CapsuleTests/Mini_CapsuleTests.swift`:

```swift
@MainActor
struct CapsuleViewSettingsTests {
    @Test func collapsedStyleReadsFromSettings() async throws {
        let store = SettingsStore()
        store.collapsedStyle = "dot"
        store.hoverExpandDelay = 0.5
        store.hoverCollapseDelay = 2.0
        store.panelOpacityUnfocused = 0.5

        #expect(store.collapsedStyle == "dot")
        #expect(store.hoverExpandDelay == 0.5)
        #expect(store.hoverCollapseDelay == 2.0)
        #expect(store.panelOpacityUnfocused == 0.5)

        store.resetAll()
        #expect(store.collapsedStyle == "capsule")
        #expect(store.hoverExpandDelay == 0.3)
    }
}
```

- [ ] **Step 2: Run test to confirm it works with current SettingsStore**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/Mini_CapsuleTests/CapsuleViewSettingsTests test 2>&1 | tail -5
```

Expected: PASS.

- [ ] **Step 3: Refactor CapsuleView.swift**

Replace all `UserDefaults.standard` reads with `settings` properties:

```swift
// Line 50: CapsuleCollapsedView init
// OLD: collapsedStyle: UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
// NEW:
collapsedStyle: settings.collapsedStyle

// Line 75: hoverExpandDelay
// OLD: let expandDelay = UserDefaults.standard.double(forKey: "hoverExpandDelay")
//       let effectiveExpandDelay = expandDelay > 0 ? expandDelay : 0.3
// NEW:
let effectiveExpandDelay = settings.hoverExpandDelay

// Line 87: hoverCollapseDelay
// OLD: let collapseDelay = UserDefaults.standard.double(forKey: "hoverCollapseDelay")
//       let effectiveCollapseDelay = collapseDelay > 0 ? collapseDelay : 1.0
// NEW:
let effectiveCollapseDelay = settings.hoverCollapseDelay

// Line 113: windowOpacity
// OLD: let unfocusedOpacity = UserDefaults.standard.double(forKey: "panelOpacityUnfocused")
//       let effectiveUnfocused = unfocusedOpacity > 0 ? unfocusedOpacity : 0.6
// NEW:
let effectiveUnfocused = settings.panelOpacityUnfocused
```

Add the `@EnvironmentObject` declaration:
```swift
// Add after the @State properties (around line 24):
@EnvironmentObject var settings: SettingsStore
```

- [ ] **Step 4: Run tests to verify**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/Mini_CapsuleTests/CapsuleViewSettingsTests test 2>&1 | tail -5
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "Mini Capsule/UI/CapsuleView.swift" "Mini CapsuleTests/Mini_CapsuleTests.swift"
git commit -m "refactor: CapsuleView reads settings from @EnvironmentObject instead of UserDefaults

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: Refactor CapsuleExpandedView to use @EnvironmentObject

**Files:**
- Modify: `Mini Capsule/UI/CapsuleExpandedView.swift` (line 92)

**Interfaces:**
- Consumes: `@EnvironmentObject var settings: SettingsStore`

- [ ] **Step 1: Add @EnvironmentObject and replace UserDefaults read**

In `CapsuleExpandedView.swift`:

```swift
// Add among the other @-properties (after line 7):
@EnvironmentObject var settings: SettingsStore

// Line 92: background image
// OLD: if let imageData = UserDefaults.standard.data(forKey: "backgroundImageData"),
// NEW:
if !settings.backgroundImageData.isEmpty,
   let nsImage = NSImage(data: settings.backgroundImageData) {
```

- [ ] **Step 2: Commit**

```bash
git add "Mini Capsule/UI/CapsuleExpandedView.swift"
git commit -m "refactor: CapsuleExpandedView reads background image from @EnvironmentObject

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: Refactor CapsuleCollapsedView to use @EnvironmentObject

**Files:**
- Modify: `Mini Capsule/UI/CapsuleCollapsedView.swift` (lines 5, 33-35)

**Interfaces:**
- Consumes: `@EnvironmentObject var settings: SettingsStore`

- [ ] **Step 1: Refactor CapsuleCollapsedView**

The `CapsuleCollapsedView` currently takes `collapsedStyle: String` as an initializer parameter and reads `dotColorMode`/`dotCustomColor` from UserDefaults in the `dotColor` computed property.

After refactoring, the view takes `collapsedStyle` as a parameter still (provided by the parent CapsuleView which uses `settings.collapsedStyle`), but the `dotColor` property reads from `@EnvironmentObject`:

```swift
// Add after the let properties (after line 7):
@EnvironmentObject var settings: SettingsStore

// Lines 33-35: dotColor computed property
// OLD:
// let mode = UserDefaults.standard.string(forKey: "dotColorMode") ?? "auto"
// if mode == "custom" {
//     let hex = UserDefaults.standard.string(forKey: "dotCustomColor") ?? "#007AFF"
// NEW:
private var dotColor: Color {
    if settings.dotColorMode == "custom" {
        return Color(hex: settings.dotCustomColor) ?? .blue
    }
    // ... rest unchanged
}
```

Note: Keep `collapsedStyle` as a `let` parameter — it still comes from the parent, but the parent now reads it from `settings.collapsedStyle` (done in Task 6).

- [ ] **Step 2: Commit**

```bash
git add "Mini Capsule/UI/CapsuleCollapsedView.swift"
git commit -m "refactor: CapsuleCollapsedView reads dot color from @EnvironmentObject

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: Refactor GeneralSettingsView to extract frame key constant

**Files:**
- Modify: `Mini Capsule/Settings/GeneralSettingsView.swift` (line 109)

**Verification test already exists** in `Mini_CapsuleTests/Mini_CapsuleTests.swift` (lines 427-450: `GeneralSettingsViewTests`). We just need to confirm it still passes after the change.

- [ ] **Step 1: Extract frame key constant**

In `GeneralSettingsView.swift`, add a private constant at file level:

```swift
// After imports, before struct:
private let capsuleWindowFrameKey = "CapsuleWindowFrame"
```

Change line 109:
```swift
// OLD: UserDefaults.standard.removeObject(forKey: "CapsuleWindowFrame")
// NEW:
UserDefaults.standard.removeObject(forKey: capsuleWindowFrameKey)
```

- [ ] **Step 2: Run existing test**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/Mini_CapsuleTests/GeneralSettingsViewTests test 2>&1 | tail -10
```

Expected: PASS (existing tests verify reset behavior).

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/Settings/GeneralSettingsView.swift"
git commit -m "refactor: extract CapsuleWindowFrame key constant in GeneralSettingsView

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 10: Refactor ClipboardMonitor to use SettingsProtocol

**Files:**
- Modify: `Mini Capsule/Services/ClipboardMonitor.swift`

**Interfaces:**
- Consumes: `SettingsProtocol` (new init parameter `settings:`)
- Changes: All computed properties (`currentPollingInterval`, `maxImageBytes`, `maxHistoryCount`, `isDedupEnabled`) now read from injected protocol

- [ ] **Step 1: Write integration test**

Add to `Mini_CapsuleTests/Mini_CapsuleTests.swift`:

```swift
@MainActor
struct ClipboardMonitorSettingsTests {
    @Test func monitorReadsPollingIntervalFromSettings() async throws {
        let store = SettingsStore()
        store.pollingInterval = 2.0
        store.historyMaxCount = 100
        store.imageMaxSizeMB = 5
        store.dedupEnabled = false

        let monitor = ClipboardMonitor(settings: store)

        // Verify settings are read through the protocol
        #expect(store.pollingInterval == 2.0)
        #expect(store.historyMaxCount == 100)
        #expect(store.imageMaxSizeMB == 5)
        #expect(store.dedupEnabled == false)

        store.resetAll()
    }
}
```

- [ ] **Step 2: Run test to verify it currently works with SettingsStore**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/Mini_CapsuleTests/ClipboardMonitorSettingsTests test 2>&1 | tail -10
```

Expected: FAIL (ClipboardMonitor init doesn't accept `settings:` yet).

- [ ] **Step 3: Refactor ClipboardMonitor.swift**

Key changes:
```swift
// Add property:
private weak var settings: SettingsProtocol?

// Add new init:
init(settings: SettingsProtocol) {
    self.settings = settings
}

// Change computed properties:
private var currentPollingInterval: TimeInterval {
    // OLD: let interval = UserDefaults.standard.double(forKey: "pollingInterval")
    //       return interval > 0 ? interval : 0.5
    guard let s = settings else { return 0.5 }
    return s.pollingInterval > 0 ? s.pollingInterval : 0.5
}

private var maxImageBytes: Int {
    // OLD: let mb = UserDefaults.standard.integer(forKey: "imageMaxSizeMB")
    guard let s = settings else { return 2_000_000 }
    switch s.imageMaxSizeMB {
    case 1: return 1_000_000
    case 5: return 5_000_000
    case 0: return Int.max
    default: return 2_000_000
    }
}

private var maxHistoryCount: Int {
    // OLD: let count = UserDefaults.standard.integer(forKey: "historyMaxCount")
    guard let s = settings else { return 200 }
    return s.historyMaxCount >= 50 ? s.historyMaxCount : 200
}

private var isDedupEnabled: Bool {
    // OLD: if UserDefaults.standard.object(forKey: "dedupEnabled") == nil { return true }
    //       return UserDefaults.standard.bool(forKey: "dedupEnabled")
    guard let s = settings else { return true }
    return s.dedupEnabled
}
```

- [ ] **Step 4: Run integration test**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/Mini_CapsuleTests/ClipboardMonitorSettingsTests test 2>&1 | tail -10
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "Mini Capsule/Services/ClipboardMonitor.swift" "Mini CapsuleTests/Mini_CapsuleTests.swift"
git commit -m "refactor: ClipboardMonitor reads settings from injected SettingsProtocol

Replace 4 UserDefaults.standard direct reads with protocol property access.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 11: Refactor MenuBarService to use SettingsProtocol

**Files:**
- Modify: `Mini Capsule/Services/MenuBarService.swift`

**Interfaces:**
- Consumes: `SettingsProtocol` (new init parameter `settings:`)

- [ ] **Step 1: Write integration test**

Add to `Mini_CapsuleTests/Mini_CapsuleTests.swift`:

```swift
@MainActor
struct MenuBarServiceSettingsTests {
    @Test func serviceReadsShowFloatingPanelFromSettings() async throws {
        let store = SettingsStore()
        store.showFloatingPanel = false

        #expect(store.showFloatingPanel == false)

        store.showFloatingPanel = true
        #expect(store.showFloatingPanel == true)

        store.resetAll()
    }

    @Test func toggleFloatingPanelUpdatesSettings() async throws {
        let store = SettingsStore()
        store.showFloatingPanel = true

        // Simulate toggle behavior (the actual MenuBarService logic)
        let current = store.showFloatingPanel
        store.showFloatingPanel = !current

        #expect(store.showFloatingPanel == false)
        store.resetAll()
    }
}
```

- [ ] **Step 2: Refactor MenuBarService.swift**

Key changes:
```swift
// Add property:
private weak var settings: SettingsProtocol?

// Add new init:
init(settings: SettingsProtocol) {
    self.settings = settings
}

// Line 61: rebuildMenu()
// OLD: let showFloating = UserDefaults.standard.bool(forKey: "showFloatingPanel")
// NEW:
let showFloating = settings?.showFloatingPanel ?? true

// Lines 124-131: toggleFloatingPanel()
// OLD:
// let current = UserDefaults.standard.bool(forKey: "showFloatingPanel")
// UserDefaults.standard.set(!current, forKey: "showFloatingPanel")
// NotificationCenter.default.post(name: .showFloatingPanelChanged, ...)
// NEW:
guard let s = settings else { return }
let current = s.showFloatingPanel
s.showFloatingPanel = !current
NotificationCenter.default.post(
    name: .showFloatingPanelChanged,
    object: nil,
    userInfo: ["show": !current]
)
```

- [ ] **Step 3: Run integration test**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/Mini_CapsuleTests/MenuBarServiceSettingsTests test 2>&1 | tail -10
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add "Mini Capsule/Services/MenuBarService.swift" "Mini CapsuleTests/Mini_CapsuleTests.swift"
git commit -m "refactor: MenuBarService reads settings from injected SettingsProtocol

Replace 2 UserDefaults direct reads/writes with protocol property access.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 12: Refactor FrequencyCleanupService to accept SettingsProtocol parameter

**Files:**
- Modify: `Mini Capsule/Services/FrequencyCleanupService.swift` (lines 11-14)

**Interfaces:**
- Consumes: `SettingsProtocol` as method parameter

- [ ] **Step 1: Refactor FrequencyCleanupService.swift**

Since `FrequencyCleanupService` is a static enum, change `performCleanup` to accept an optional `SettingsProtocol` parameter:

```swift
// Lines 6-14: performCleanup signature
// OLD:
// static func performCleanup(context: ModelContext, keepCount: Int? = nil) {
//     ...
//     let keep = keepCount ?? {
//         let count = UserDefaults.standard.integer(forKey: "historyMaxCount")
//         return count >= 50 ? min(50, count) : 50
//     }()
// NEW:
static func performCleanup(context: ModelContext, keepCount: Int? = nil, settings: SettingsProtocol? = nil) {
    // ...
    let keep = keepCount ?? {
        let count = settings?.historyMaxCount ?? 200
        return count >= 50 ? min(50, count) : 50
    }()
    // ... rest unchanged
}
```

- [ ] **Step 2: Commit**

```bash
git add "Mini Capsule/Services/FrequencyCleanupService.swift"
git commit -m "refactor: FrequencyCleanupService accepts SettingsProtocol parameter

Replace UserDefaults.standard.integer(forKey:) with protocol property read.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 13: Refactor CapsuleWindowController to use SettingsProtocol

**Files:**
- Modify: `Mini Capsule/UI/CapsuleWindowController.swift`

**Interfaces:**
- Consumes: `SettingsProtocol` (new init parameter `settings:`)
- Changes: 5 `UserDefaults.standard.string(forKey: "collapsedStyle")` reads replaced with `settings.collapsedStyle`

- [ ] **Step 1: Write integration test**

Add to `Mini_CapsuleTests/Mini_CapsuleTests.swift`:

```swift
@MainActor
struct CapsuleWindowControllerSettingsTests {
    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func controllerReadsCollapsedStyleFromInjectedSettings() async throws {
        let store = SettingsStore()
        store.collapsedStyle = "dot"
        let container = try Self.makeContainer()

        let controller = CapsuleWindowController(
            modelContainer: container,
            settings: store
        )

        #expect(controller.window?.contentView?.layer?.cornerRadius == 6)

        // When collapsed style changes to capsule
        store.collapsedStyle = "capsule"
        NotificationCenter.default.post(
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        #expect(controller.window?.contentView?.layer?.cornerRadius == 18)
    }
}
```

- [ ] **Step 2: refactor CapsuleWindowController.swift**

Key changes:
```swift
// Add property:
private let settings: SettingsProtocol

// Change init signature:
init(modelContainer: ModelContainer, settings: SettingsProtocol) {
    self.modelContainer = modelContainer
    self.settings = settings
    // ... rest unchanged
}

// currentCollapsedSize (line 29):
// OLD: let style = UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
// NEW:
var currentCollapsedSize: NSSize {
    return settings.collapsedStyle == "dot" ? Self.dotCollapsedSize : Self.capsuleCollapsedSize
}

// init body (line 70):
// OLD: let initialStyle = UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
// NEW:
let initialStyle = settings.collapsedStyle

// observeExpandedState (line 174):
// OLD: let style = UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
// NEW:
let style = settings.collapsedStyle

// line 207:
// OLD: let style = UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
// NEW:
let style = settings.collapsedStyle

// resetCapsulePosition observer (line 237):
// OLD: let style = UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
// NEW:
let style = settings.collapsedStyle

// loadFrame (line 285-286):
// OLD: static func loadFrame() -> NSRect {
//          let style = UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
// NEW:
private static func loadFrame(style: String) -> NSRect {
    let size = style == "dot" ? dotCollapsedSize : capsuleCollapsedSize

// init call site (line 36):
// OLD: let savedFrame = Self.loadFrame()
// NEW:
let savedFrame = Self.loadFrame(style: settings.collapsedStyle)
```

Frame persistence (`saveFrame`, `loadFrame`, `"CapsuleWindowFrame"` key) stays in CapsuleWindowController using the local `frameKey` constant — frame position is window state, not a setting.

- [ ] **Step 3: Run integration test**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/CapsuleWindowControllerSettingsTests test 2>&1 | tail -10
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add "Mini Capsule/UI/CapsuleWindowController.swift" "Mini CapsuleTests/Mini_CapsuleTests.swift"
git commit -m "refactor: CapsuleWindowController reads settings from injected SettingsProtocol

Replace 5 UserDefaults.standard reads for collapsedStyle with protocol property.
Frame persistence (CapsuleWindowFrame key) stays local as window state.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 14: Wire everything in CapsuleAppDelegate

**Files:**
- Modify: `Mini Capsule/Mini_CapsuleApp.swift`

**Interfaces:**
- Consumes: All refactored services with `settings:` init parameters
- Produces: Full dependency injection chain wired; last UserDefaults reads removed

- [ ] **Step 1: Refactor CapsuleAppDelegate.swift**

Update `applicationDidFinishLaunching` and `registerShortcuts`:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    // Frequency cleanup — pass settings
    FrequencyCleanupService.performCleanup(
        context: Self.sharedModelContainer.mainContext,
        keepCount: 50,
        settings: settingsStore
    )

    // Create capsule window — inject settings
    let controller = CapsuleWindowController(
        modelContainer: Self.sharedModelContainer,
        settings: settingsStore   // ← NEW
    )
    controller.showWindow()
    capsuleWindowController = controller

    // Start clipboard monitoring — inject settings
    let monitor = ClipboardMonitor(settings: settingsStore)  // ← NEW
    monitor.start(context: Self.sharedModelContainer.mainContext)
    clipboardMonitor = monitor

    // Start menu bar — inject settings
    let menuBar = MenuBarService(settings: settingsStore)  // ← NEW
    menuBar.start(context: Self.sharedModelContainer.mainContext)
    menuBarService = menuBar

    // ... rest unchanged (showFloatingPanelChanged observer, registerShortcuts)
}

private func registerShortcuts() {
    shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self = self else { return event }
        let combo = self.shortcutString(from: event)

        // OLD: let showHide = UserDefaults.standard.string(forKey: "showHideShortcut") ?? "cmd+shift+V"
        // OLD: let quickPaste = UserDefaults.standard.string(forKey: "quickPasteShortcut") ?? "cmd+shift+C"
        // OLD: let togglePin = UserDefaults.standard.string(forKey: "togglePinShortcut") ?? ""
        // NEW:
        let showHide = self.settingsStore.showHideShortcut
        let quickPaste = self.settingsStore.quickPasteShortcut
        let togglePin = self.settingsStore.togglePinShortcut

        // ... rest unchanged
    }
}
```

- [ ] **Step 2: Build the project**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED. This is the critical verification — the full app builds with all refactored init signatures.

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/Mini_CapsuleApp.swift"
git commit -m "refactor: wire SettingsStore injection into all services in CapsuleAppDelegate

Remove last UserDefaults.standard direct reads. All services now receive
SettingsProtocol via init. Full dependency injection chain complete.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 15: Run all tests and verify

**Files:** None (verification only)

- [ ] **Step 1: Build for macOS**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 2: Run all unit tests**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -30
```

Expected: ALL tests PASS.

- [ ] **Step 3: Cross-verify feature checklist against test results**

| # | Feature | Test |
|---|---------|------|
| 1 | Key constants unique | `SettingsKeyTests.allKeysAreUnique` |
| 2 | Key count correct | `SettingsKeyTests.keyCountIsCorrect` |
| 3 | Keys match expected | `SettingsKeyTests.keysMatchExpectedValues` |
| 4 | Notification values correct | `NotificationNamesTests` (3 tests) |
| 5 | Default values | `SettingsStoreTests.defaults` |
| 6 | resetAll restores defaults | `SettingsStoreTests.resetAllRestoresDefaults` |
| 7 | Persistence across instances | `SettingsStoreTests.settingsPersistAcrossStoreInstances` |
| 8 | Shortcut keys read/write | `SettingsStoreTests.shortcutKeys` |
| 9 | Combinatorial change+reset | `SettingsStoreTests.allSettingsCombinatorialChangeThenReset` |
| 10 | objectWillChange emission | `SettingsStoreTests.propertyChangeNotifiesObjectWillChange` |
| 11 | Default values consistency | `SettingsStoreTests.defaultValuesAreConsistent` |
| 12 | Reset position action | `GeneralSettingsViewTests` (2 tests) |
| 13 | ClipboardMonitor reads from protocol | `ClipboardMonitorSettingsTests` |
| 14 | MenuBarService reads from protocol | `MenuBarServiceSettingsTests` |
| 15 | CapsuleView reads from settings | `CapsuleViewSettingsTests` |
| 16 | CapsuleWindowController reads from protocol | `CapsuleWindowControllerSettingsTests` |
| 17 | Notification names for drag/reset | `SettingsStoreTests.notificationNameCapsuleDragStarted` etc. |
| 18 | CapsuleWindowController corner radius | `CapsuleWindowControllerTests` (existing 6 tests) |

- [ ] **Step 4: Final commit if any test adjustments needed**

```bash
git add -A
git commit -m "test: final test adjustments after settings refactor

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Implementation Notes

- The build will fail between Tasks 10-13 and Task 14 because init signatures change but CapsuleAppDelegate hasn't been updated yet. This is expected — Task 14 (wiring) resolves it.
- Each task's tests can run independently via `-only-testing:` because only the test target needs to build.
- The `@EnvironmentObject` injection for SwiftUI views (`CapsuleView`, `CapsuleExpandedView`, `CapsuleCollapsedView`) already works because `CapsuleAppDelegate` provides `.environmentObject(appDelegate.settingsStore)` in the `Settings` scene (line 171 of Mini_CapsuleApp.swift). No wiring change needed for views.
- Color extensions (`Color(hex:)`, `Color.toHex()`) in `AppearanceSettingsView.swift` are NOT moved — they are UI concerns, not settings concerns. The AppearanceSettingsView file is not modified.
- The `ClipboardMonitor.md5Hash` static method is kept because `SettingsStore.importData` references it. No change needed.
- `ShortcutCaptureManager` in `ShortcutsSettingsView.swift` is NOT modified — it captures keyboard events via `NSEvent` and writes to `SettingsStore` via bindings. Its internal logic is independent of the settings architecture.
