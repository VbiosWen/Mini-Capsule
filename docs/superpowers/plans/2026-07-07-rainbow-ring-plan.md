# Rainbow Ring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the solid-color dot collapsed style with a static rainbow gradient ring with adjustable diameter (20–200px, default 60px).

**Architecture:** The ring replaces the current `dotView` in `CapsuleCollapsedView` using an `AngularGradient` stroke. Settings are migrated from two keys (`dotColorMode`, `dotCustomColor`) to one (`ringDiameter`). The window controller's dot collapsed size and corner radius become dynamic, driven by `ringDiameter`.

**Tech Stack:** SwiftUI, AppKit (CapsulePanel/CapsuleWindowController), Swift Testing, @Observable (SettingsStore), UserDefaults

## Global Constraints

- Ring is always rainbow — no color mode, no custom color
- Ring diameter range: 20–200px, step 1px, default 60px
- Static gradient (no animation)
- Line width scales as `max(2, diameter * 0.05)` — minimum 2px
- Capture scale animation and shadow preserved from old dot
- Window corner radius for dot style: `ringDiameter / 2`
- Window collapsed size for dot style: `NSSize(width: ringDiameter, height: ringDiameter)`
- `collapsedStyle` key value stays `"dot"` — no migration needed
- Remove `dotColorMode` and `dotCustomColor` from SettingsKey, SettingsProtocol, SettingsStore, and all tests

---

### Task 1: Data Layer — Update SettingsKey and SettingsProtocol

**Files:**
- Modify: `Mini Capsule/Settings/SettingsKey.swift`
- Modify: `Mini Capsule/Settings/SettingsProtocol.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `SettingsKey.ringDiameter: SettingsKey`, `SettingsProtocol.ringDiameter: Double { get set }`; removes `SettingsKey.dotColorMode`, `SettingsKey.dotCustomColor`, `SettingsProtocol.dotColorMode`, `SettingsProtocol.dotCustomColor`

- [ ] **Step 1: Remove old keys, add new key in SettingsKey.swift**

Replace the Appearance section of the `SettingsKey` enum:

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
    case ringDiameter

    /// Window frame position persistence key (JSON-encoded [String: CGFloat]).
    case capsuleWindowFrame
}
```

- [ ] **Step 2: Update SettingsProtocol.swift**

Remove `dotColorMode` and `dotCustomColor` from the Appearance section, add `ringDiameter`:

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
    var ringDiameter: Double { get set }
    var capsuleWindowFrame: Data { get set }

    // MARK: - Actions
    func resetAll()
    func exportData(context: ModelContext) -> Data?
    func importData(_ data: Data, context: ModelContext) throws
    func clearAllHistory(context: ModelContext)
}
```

- [ ] **Step 3: Run tests to verify compilation errors (expected — SettingsStore no longer conforms)**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: BUILD FAILED — SettingsStore missing `ringDiameter` property, references to `dotColorMode`/`dotCustomColor`

- [ ] **Step 4: Commit**

```bash
git add "Mini Capsule/Settings/SettingsKey.swift" "Mini Capsule/Settings/SettingsProtocol.swift"
git commit -m "feat: add ringDiameter, remove dotColorMode/dotCustomColor from SettingsKey and protocol"
```

---

### Task 2: Data Layer — Update SettingsStore

**Files:**
- Modify: `Mini Capsule/Settings/SettingsStore.swift`

**Interfaces:**
- Consumes: `SettingsKey.ringDiameter` (from Task 1), `SettingsProtocol` (from Task 1)
- Produces: `SettingsStore.ringDiameter: Double` (get/set UserDefaults), updated `resetAll()`

- [ ] **Step 1: Remove dotColorMode and dotCustomColor properties**

Delete lines 230–256 in `SettingsStore.swift` (the two `var dotColorMode` and `var dotCustomColor` blocks).

- [ ] **Step 2: Add ringDiameter property in the Appearance section**

Insert after `backgroundImageData` property, before the `// MARK: - Window Frame` comment:

```swift
    var ringDiameter: Double {
        get {
            access(keyPath: \.ringDiameter)
            return UserDefaults.standard.object(forKey: SettingsKey.ringDiameter.rawValue) as? Double ?? 60
        }
        set {
            withMutation(keyPath: \.ringDiameter) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.ringDiameter.rawValue)
            }
        }
    }
```

- [ ] **Step 3: Update resetAll()**

Remove the two lines:
```swift
        dotColorMode = "auto"
        dotCustomColor = "#007AFF"
```

Add after `backgroundImageData = Data()`:
```swift
        ringDiameter = 60
```

- [ ] **Step 4: Run tests to verify SettingsStore compiles but tests still fail**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED (SettingsStore now compiles; test file references to old keys will fail at test build time since tests are a separate target)

- [ ] **Step 5: Commit**

```bash
git add "Mini Capsule/Settings/SettingsStore.swift"
git commit -m "feat: add ringDiameter property, remove dot color settings from SettingsStore"
```

---

### Task 3: View Layer — Replace dotView with ringView in CapsuleCollapsedView

**Files:**
- Modify: `Mini Capsule/UI/CapsuleCollapsedView.swift`

**Interfaces:**
- Consumes: `SettingsStore.ringDiameter` (from Task 2)
- Produces: `ringView` replaces `dotView`; removes `dotColor` computed property

- [ ] **Step 1: Replace dotView with ringView**

Change the `dotView` computed property (lines 24–35) to `ringView`:

```swift
    // MARK: - Ring variant (rainbow)

    private var ringView: some View {
        Circle()
            .stroke(
                AngularGradient(
                    colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                    center: .center
                ),
                lineWidth: max(2, settings.ringDiameter * 0.05)
            )
            .frame(width: settings.ringDiameter, height: settings.ringDiameter)
            .scaleEffect(isCapturing ? 1.3 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isCapturing)
            .shadow(
                color: .black.opacity(0.15),
                radius: 4,
                y: 2
            )
    }
```

- [ ] **Step 2: Update the style switch to use ringView**

Change line 13 from `dotView` to `ringView`:
```swift
        switch collapsedStyle {
        case "dot":
            ringView
        case "icon":
            iconView
        default:
            capsuleView
        }
```

- [ ] **Step 3: Remove the dotColor computed property**

Delete lines 37–48 (the entire `dotColor` computed property).

- [ ] **Step 4: Verify compilation**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED (CapsuleCollapsedView no longer references dotColorMode/dotCustomColor)

- [ ] **Step 5: Commit**

```bash
git add "Mini Capsule/UI/CapsuleCollapsedView.swift"
git commit -m "feat: replace dotView with rainbow ringView using AngularGradient"
```

---

### Task 4: Settings UI — Update AppearanceSettingsView

**Files:**
- Modify: `Mini Capsule/Settings/AppearanceSettingsView.swift`

**Interfaces:**
- Consumes: `SettingsStore.ringDiameter` (from Task 2)
- Produces: Updated appearance settings form with ring diameter slider, dot color section removed

- [ ] **Step 1: Remove the dot color section (lines 67–87)**

Delete the entire `Section { ... } header: { Text("圆点") }` block (the "圆点颜色模式" picker and "自定义颜色" color picker).

- [ ] **Step 2: Add the ring diameter section**

Insert before the closing `}` of the `Form` (after the background section closing `}`):

```swift
            Section {
                LabeledContent("圆环大小") {
                    HStack(spacing: 8) {
                        Slider(value: Bindable(settings).ringDiameter, in: 20...200, step: 1)
                            .frame(width: 150)
                        Text("\(Int(settings.ringDiameter))px")
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                Text("圆环")
            } footer: {
                Text("圆环模式下的彩虹圆环直径，范围 20–200px。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
```

- [ ] **Step 3: Verify compilation**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add "Mini Capsule/Settings/AppearanceSettingsView.swift"
git commit -m "feat: replace dot color settings with ring diameter slider"
```

---

### Task 5: Window Controller — Dynamic Dot Size and Corner Radius

**Files:**
- Modify: `Mini Capsule/UI/CapsuleWindowController.swift`

**Interfaces:**
- Consumes: `SettingsStore.ringDiameter` (from Task 2), `SettingsKey.ringDiameter` (from Task 1)
- Produces: Dynamic collapsed size for dot style, dynamic corner radius for dot style

- [ ] **Step 1: Remove static dotCollapsedSize, add instance computed property, fix loadFrame**

Replace line 25:
```swift
    private static let dotCollapsedSize = NSSize(width: 12, height: 12)
```
With an instance computed property:
```swift
    private var dotCollapsedSize: NSSize {
        let diameter = settingsStore.ringDiameter
        return NSSize(width: diameter, height: diameter)
    }
```

Update `currentCollapsedSize` (line 31) to remove `Self.` prefix since it's no longer static:
```swift
        case "dot": return dotCollapsedSize
```

Update the static `loadFrame` method (line 347) — read ringDiameter from UserDefaults directly since static methods can't access instance properties:
```swift
        case "dot":
            let diameter = UserDefaults.standard.object(forKey: SettingsKey.ringDiameter.rawValue) as? Double ?? 60
            size = NSSize(width: diameter, height: diameter)
```

- [ ] **Step 2: Update init cornerRadius for dot style**

In `init`, change line 87 from:
```swift
        case "dot": initCornerRadius = 6
```
To:
```swift
        case "dot": initCornerRadius = settingsStore.ringDiameter / 2
```

- [ ] **Step 3: Update observeExpandedState cornerRadius for dot style**

In `observeExpandedState()`, change the dot case in the collapse cornerRadius switch (line 209) from:
```swift
                    case "dot": cornerRadius = 6
```
To:
```swift
                    case "dot": cornerRadius = self.settingsStore.ringDiameter / 2
```

- [ ] **Step 4: Update UserDefaults observer cornerRadius for dot style**

In the UserDefaults.didChangeNotification observer, change line 256 from:
```swift
                case "dot": radius = 6
```
To:
```swift
                case "dot": radius = self.settingsStore.ringDiameter / 2
```

- [ ] **Step 5: Update UserDefaults observer size for dot style**

In the same UserDefaults observer, the dot size switch (lines 261–265) currently uses `Self.dotCollapsedSize`. It already calls `self.currentCollapsedSize` indirectly through `self.settingsStore.collapsedStyle`. Since `currentCollapsedSize` now returns the dynamic `dotCollapsedSize` computed property, this is already correct — no change needed. But verify the switch at line 261:

Change from:
```swift
                case "dot": size = Self.dotCollapsedSize
```
To:
```swift
                case "dot": size = self.dotCollapsedSize
```

- [ ] **Step 6: Update resetPosition observer for dot style**

In the resetPosition observer, change line 292 from:
```swift
                case "dot": size = Self.dotCollapsedSize
```
To:
```swift
                case "dot": size = self.dotCollapsedSize
```

- [ ] **Step 7: Verify compilation**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add "Mini Capsule/UI/CapsuleWindowController.swift"
git commit -m "feat: dynamic dot collapsed size and corner radius from ringDiameter"
```

---

### Task 6: Tests — Update SettingsKeyTests

**Files:**
- Modify: `Mini CapsuleTests/SettingsKeyTests.swift`

**Interfaces:**
- Consumes: `SettingsKey` changes from Task 1
- Produces: Updated key count (19), updated expected keys set

- [ ] **Step 1: Update key count test**

Change line 12 from:
```swift
        #expect(SettingsKey.allCases.count == 20, "Expected 20 settings keys")
```
To:
```swift
        #expect(SettingsKey.allCases.count == 19, "Expected 19 settings keys")
```

- [ ] **Step 2: Update expected keys set**

Replace the `expected` set (lines 16–25) — remove `"dotColorMode"` and `"dotCustomColor"`, add `"ringDiameter"`:

```swift
        let expected: Set<String> = [
            "historyMaxCount", "imageMaxSizeMB", "pollingInterval",
            "cleanupOnStartup", "dedupEnabled",
            "showHideShortcut", "quickPasteShortcut", "togglePinShortcut",
            "iCloudSyncEnabled", "launchAtLogin", "showInMenuBar",
            "showFloatingPanel", "collapsedStyle", "hoverExpandDelay",
            "hoverCollapseDelay", "panelOpacityUnfocused",
            "backgroundImageData", "ringDiameter",
            "capsuleWindowFrame"
        ]
```

- [ ] **Step 3: Run SettingsKeyTests to verify they pass**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:Mini_CapsuleTests/SettingsKeyTests test 2>&1 | tail -15`
Expected: TEST SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add "Mini CapsuleTests/SettingsKeyTests.swift"
git commit -m "test: update SettingsKeyTests for ringDiameter migration"
```

---

### Task 7: Tests — Update Mini_CapsuleTests (SettingsStore tests)

**Files:**
- Modify: `Mini CapsuleTests/Mini_CapsuleTests.swift`

**Interfaces:**
- Consumes: `SettingsStore` changes from Task 2
- Produces: All SettingsStore tests pass with new ringDiameter property

- [ ] **Step 1: Update allKeys list**

In `SettingsStoreTests`, change lines 11–18 — remove `"dotColorMode"`, `"dotCustomColor"`, add `"ringDiameter"`:

```swift
    private static let allKeys = [
        "historyMaxCount", "imageMaxSizeMB", "pollingInterval", "cleanupOnStartup", "dedupEnabled",
        "showHideShortcut", "quickPasteShortcut", "togglePinShortcut", "iCloudSyncEnabled",
        "launchAtLogin", "showInMenuBar", "showFloatingPanel", "collapsedStyle",
        "hoverExpandDelay", "hoverCollapseDelay",
        "panelOpacityUnfocused", "backgroundImageData", "ringDiameter",
        "capsuleWindowFrame"
    ]
```

- [ ] **Step 2: Update defaults() test**

Replace lines 47–48:
```swift
        #expect(store.dotColorMode == "auto")
        #expect(store.dotCustomColor == "#007AFF")
```
With:
```swift
        #expect(store.ringDiameter == 60)
```

- [ ] **Step 3: Update resetAllRestoresDefaults() test**

Replace lines 71–72:
```swift
        store.dotColorMode = "custom"
        store.dotCustomColor = "#FF0000"
```
With:
```swift
        store.ringDiameter = 120
```

Replace lines 94–95:
```swift
        #expect(store.dotColorMode == "auto")
        #expect(store.dotCustomColor == "#007AFF")
```
With:
```swift
        #expect(store.ringDiameter == 60)
```

- [ ] **Step 4: Update allSettingsCombinatorialChangeThenReset() test**

Replace lines 145–146:
```swift
        store.dotColorMode = "custom"
        store.dotCustomColor = "#FF0000"
```
With:
```swift
        store.ringDiameter = 120
```

Replace lines 150–151:
```swift
        #expect(store.dotColorMode == "custom")
        #expect(store.dotCustomColor == "#FF0000")
```
With:
```swift
        #expect(store.ringDiameter == 120)
```

Replace lines 159–160:
```swift
        #expect(store.dotColorMode == "auto")
        #expect(store.dotCustomColor == "#007AFF")
```
With:
```swift
        #expect(store.ringDiameter == 60)
```

- [ ] **Step 5: Update defaultValuesAreConsistent() test**

Replace lines 197–198:
```swift
        #expect(store.dotColorMode == "auto")
        #expect(store.dotCustomColor == "#007AFF")
```
With:
```swift
        #expect(store.ringDiameter == 60)
```

- [ ] **Step 6: Run all tests to verify**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test 2>&1 | tail -20`
Expected: All tests pass (TEST SUCCEEDED)

- [ ] **Step 7: Commit**

```bash
git add "Mini CapsuleTests/Mini_CapsuleTests.swift"
git commit -m "test: update SettingsStore tests for ringDiameter, remove dot color tests"
```

---

### Task 8: Tests — Update CapsuleWindowController tests

**Files:**
- Modify: `Mini CapsuleTests/Mini_CapsuleTests.swift`

**Interfaces:**
- Consumes: `CapsuleWindowController` changes from Task 5
- Produces: Corner radius tests pass with dynamic dot size

- [ ] **Step 1: Update initialCornerRadiusDot test**

Change the test at `CapsuleWindowControllerTests.initialCornerRadiusDot` (line 237). With default `ringDiameter = 60`, corner radius should be 30:

```swift
    @Test func initialCornerRadiusDot() async throws {
        let defaults = UserDefaults.standard
        defaults.set("dot", forKey: "collapsedStyle")

        let container = try Self.makeContainer()
        let controller = CapsuleWindowController(modelContainer: container, settingsStore: SettingsStore())

        #expect(controller.window?.contentView?.layer?.cornerRadius == 30)
    }
```

- [ ] **Step 2: Update updatesCornerRadiusOnStyleChangeWhenCollapsed test**

Change the expected dot cornerRadius from 6 to 30 (default ringDiameter / 2) on line 300:

```swift
        store.collapsedStyle = "dot"
        #expect(controller.window?.contentView?.layer?.cornerRadius == 30)
```

- [ ] **Step 3: Run capsulateWindowController tests**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:Mini_CapsuleTests/CapsuleWindowControllerTests test 2>&1 | tail -15`
Expected: All CapsuleWindowControllerTests pass

- [ ] **Step 4: Commit**

```bash
git add "Mini CapsuleTests/Mini_CapsuleTests.swift"
git commit -m "test: update CapsuleWindowController tests for dynamic dot cornerRadius"
```

---

### Task 9: Final Verification — Full Test Suite

**Files:**
- No code changes — verification only

- [ ] **Step 1: Run the full test suite**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test 2>&1 | grep -E "(Test Suite|TEST|passed|failed|error)" | tail -30`

Expected: All test suites pass, no failures

- [ ] **Step 2: Verify no remaining references to old settings**

```bash
grep -rn "dotColorMode\|dotCustomColor" "Mini Capsule" "Mini CapsuleTests" --include="*.swift"
```

Expected: No output (no remaining references)

- [ ] **Step 3: Commit if any cleanup was needed, or confirm done**

```bash
git status
```
