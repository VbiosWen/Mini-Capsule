# Settings Module Refactor Design

**Date:** 2026-07-07
**Status:** Approved

## Overview

Refactor the entire settings module to establish `SettingsStore` as the single source of truth, eliminate raw `UserDefaults` calls from consumers, unify notification names, and ensure every feature has automated test verification.

## Current Problems

| Problem | Detail |
|---|---|
| Hardcoded key strings | Raw `UserDefaults.standard.string(forKey: "collapsedStyle")` duplicated across 8 files with repeated defaults |
| Fake `@Published` | `SettingsStore` declares `objectWillChange` but never calls `.send()` |
| Dual access paths | Services/UI read `UserDefaults` directly instead of through `SettingsStore` |
| Scattered `Notification.Name` | Two separate extensions in `SettingsStore.swift` and `CapsuleView.swift` |
| Mixed concerns | `SettingsStore` handles settings + data export/import + clipboard history |

## Target Architecture

### File Structure

```
Settings/
├── SettingsKey.swift           // Private enum: all UserDefaults key constants
├── NotificationNames.swift     // Single file for all Notification.Name extensions
├── SettingsProtocol.swift      // Protocol exposing all settings and actions
├── SettingsStore.swift         // ObservableObject implementation
├── GeneralSettingsView.swift
├── AppearanceSettingsView.swift
├── ClipboardSettingsView.swift
├── ShortcutsSettingsView.swift
└── AdvancedSettingsView.swift
```

### Design Decisions

1. **SettingsKey is private** — only `SettingsStore` uses these constants. External consumers never see raw key strings.
2. **SettingsProtocol** — allows test mocks and explicit dependency injection for services.
3. **didSet + objectWillChange.send()** — every `@AppStorage` property notifies observers on change, making `SettingsStore` a true `ObservableObject`.
4. **All services inject `SettingsProtocol`** — `ClipboardMonitor`, `MenuBarService`, `CapsuleWindowController`, and all SwiftUI views consume settings through a single path.
5. **Notification names unified** — one file, one extension, all names documented.

---

## Design Sections

### Section 1: Key Constants & Notification Names

**SettingsKey** — private enum, not exposed outside `SettingsStore`:

```swift
enum SettingsKey: String, CaseIterable {
    case historyMaxCount, imageMaxSizeMB, pollingInterval,
         cleanupOnStartup, dedupEnabled,
         showHideShortcut, quickPasteShortcut, togglePinShortcut,
         iCloudSyncEnabled, launchAtLogin, showInMenuBar,
         showFloatingPanel, collapsedStyle, hoverExpandDelay,
         hoverCollapseDelay, panelOpacityUnfocused,
         backgroundImageData, dotColorMode, dotCustomColor
}
```

**NotificationNames** — single file consolidating all notification names (currently split between `SettingsStore.swift` and `CapsuleView.swift`).

### Section 2: SettingsProtocol + SettingsStore

**SettingsProtocol** declares all properties and actions:

```swift
protocol SettingsProtocol: AnyObject {
    // Clipboard
    var historyMaxCount: Int { get set }
    var imageMaxSizeMB: Int { get set }
    var pollingInterval: Double { get set }
    var cleanupOnStartup: Bool { get set }
    var dedupEnabled: Bool { get set }

    // Shortcuts
    var showHideShortcut: String { get set }
    var quickPasteShortcut: String { get set }
    var togglePinShortcut: String { get set }

    // General
    var launchAtLogin: Bool { get set }
    var showInMenuBar: Bool { get set }
    var showFloatingPanel: Bool { get set }
    var collapsedStyle: String { get set }
    var hoverExpandDelay: Double { get set }
    var hoverCollapseDelay: Double { get set }

    // Appearance
    var panelOpacityUnfocused: Double { get set }
    var backgroundImageData: Data { get set }
    var dotColorMode: String { get set }
    var dotCustomColor: String { get set }

    // Actions
    func resetAll()
    func exportData(context: ModelContext) -> Data?
    func importData(_ data: Data, context: ModelContext) throws
    func clearAllHistory(context: ModelContext)
}
```

**SettingsStore** implements `SettingsProtocol` and `ObservableObject`. Every `@AppStorage` property uses a `didSet` that calls `objectWillChange.send()`:

```swift
@MainActor
final class SettingsStore: ObservableObject, SettingsProtocol {
    @AppStorage(SettingsKey.pollingInterval.rawValue)
    var pollingInterval: Double = 0.5 {
        didSet { objectWillChange.send() }
    }
    // ... all other properties follow the same pattern
}
```

### Section 3: Service Layer Refactor

All services currently reading `UserDefaults.standard` directly are refactored to accept `SettingsProtocol` via init:

| Service | Current | Target |
|---|---|---|
| `ClipboardMonitor` | `UserDefaults.standard.double(forKey:)` at call site | `settings.pollingInterval` from injected protocol |
| `MenuBarService` | `UserDefaults.standard.bool(forKey:)` / `.set()` | `settings.showFloatingPanel` from injected protocol |
| `CapsuleWindowController` | `UserDefaults.standard.string(forKey:)` / `.dictionary(forKey:)` / `.removeObject(forKey:)` / `.set()` | `settings.collapsedStyle` from injected protocol; frame persistence methods refactored |
| `CapsuleView` | `UserDefaults.standard.string(forKey:)` / `.double(forKey:)` | `@EnvironmentObject var settings: SettingsStore` |
| `CapsuleExpandedView` | `UserDefaults.standard.data(forKey:)` | `@EnvironmentObject var settings: SettingsStore` |
| `CapsuleCollapsedView` | `UserDefaults.standard.string(forKey:)` | `@EnvironmentObject var settings: SettingsStore` |
| `CapsuleAppDelegate` | `UserDefaults.standard.string(forKey:)` for shortcuts | `settings.showHideShortcut` etc. via `settingsStore` |

**Dependency injection chain:** `CapsuleAppDelegate` owns the `SettingsStore` instance. It injects `settingsStore` (as `SettingsProtocol`) into `CapsuleWindowController`, `ClipboardMonitor`, `MenuBarService` at init time. SwiftUI views receive it via `.environmentObject(settingsStore)`.

**Frame persistence:** `CapsuleWindowController`'s frame save/load logic using the `"CapsuleWindowFrame"` key stays within `CapsuleWindowController` but uses a constant from `SettingsKey` instead of a hardcoded string.

### Section 4: Test & Verification Strategy

All verification is automated (unit tests, Swift Testing framework). No manual verification.

**Test file structure:**

```
Mini CapsuleTests/
├── SettingsStoreTests.swift        # Existing — extended with new cases
├── SettingsKeyTests.swift          # New: verify all keys, no duplicates, correct count
├── GeneralSettingsTests.swift      # New: launchAtLogin SMAppService, ensureOneModeEnabled
├── AppearanceSettingsTests.swift   # New: opacity range, background image compression
├── ClipboardSettingsTests.swift    # New: polling notification, dedup toggle
├── ShortcutsSettingsTests.swift    # New: shortcut conflict detection logic
├── CapIntegrationTests.swift       # New: ClipboardMonitor reads correct interval from injected settings
└── ResetPositionTests.swift        # Existing GeneralSettingsViewTests — moved/expanded
```

**Feature verification checklist (run all tests, all must pass):**

| # | Feature | Test Coverage |
|---|---|---|
| 1 | Key constants | No duplicates across `allCases`, count == expected |
| 2 | Default values | Fresh store has all expected defaults |
| 3 | resetAll | Modified settings restored to defaults |
| 4 | Persistence across instances | Value written in store1 visible in store2 |
| 5 | objectWillChange emission | Value change triggers publisher |
| 6 | launchAtLogin | SMAppService register/unregister calls |
| 7 | ensureOneModeEnabled | Both off → menu bar auto-enabled |
| 8 | showFloatingPanel notification | Notification posted on toggle |
| 9 | collapsedStyle | Write then read matches |
| 10 | hoverExpandDelay | Write then read matches |
| 11 | hoverCollapseDelay | Write then read matches |
| 12 | panelOpacityUnfocused | Write then read matches, clamped to 0.3–1.0 |
| 13 | Background image compression | >2MB image auto-compressed |
| 14 | dotColorMode | "auto" / "custom" toggle works |
| 15 | dotCustomColor | Hex parse/roundtrip correct |
| 16 | pollingInterval notification | `pollingIntervalDidChange` posted on change |
| 17 | Shortcut conflict detection | Internal conflict (duplicate within app) detected |
| 18 | Shortcut system conflict | Known system shortcuts flagged |
| 19 | Shortcut capture manager | Recording starts/stops, captures key combo |
| 20 | Data export | ClipItems serialized to valid JSON |
| 21 | Data import | JSON deserialized, text/images inserted, dedup applied |
| 22 | Clear all history | All ClipItems removed from context |
| 23 | Service injection | Service reads correct value from protocol, not UserDefaults |
| 24 | Reset capsule position | Frame key removed + notification posted |

### Non-Goals

- No UI test changes — the existing `Mini_CapsuleUITests` files are not modified.
- No behavioral changes to settings — all defaults, ranges, and side effects remain identical.
- No new settings added — scope limited to restructuring existing functionality.
- No iCloud Sync implementation — the "coming soon" placeholder is preserved as-is.
