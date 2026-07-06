# System Settings Window — Design Spec

**Date**: 2026-07-06
**Status**: Draft
**App**: Mini Capsule (macOS clipboard manager)

---

## Overview

Add a system settings window accessible from the gear button in `CapsuleExpandedView`. The window uses macOS-native `Settings` scene with `TabView` (three tabs: Clipboard, Shortcuts, Advanced). Settings are persisted via `UserDefaults` through `@AppStorage`, with a centralized `SettingsStore` observable object. Most settings take effect immediately; polling interval changes restart the clipboard monitor timer automatically.

## Architecture

```
Mini Capsule/
├── Settings/
│   ├── SettingsStore.swift              # @AppStorage wrapper, ObservableObject
│   ├── ClipboardSettingsView.swift      # Clipboard tab
│   ├── ShortcutsSettingsView.swift      # Keyboard shortcuts tab
│   └── AdvancedSettingsView.swift       # Advanced tab (sync, export/import, reset)
├── Mini_CapsuleApp.swift                # Add Settings scene
└── UI/CapsuleExpandedView.swift         # Wire gear button → openSettings
```

### Data Flow

```
UserDefaults (single source of truth)
    ↕ @AppStorage
SettingsStore (ObservableObject, read/write)
    ↕ @EnvironmentObject
Settings Views (SwiftUI, auto-refresh on change)
    ↓ openSettings action
Gear button in CapsuleExpandedView
```

Non-SwiftUI consumers (`ClipboardMonitor`, `FrequencyCleanupService`) read values directly from `UserDefaults.standard` keys defined in `SettingsStore`. When polling interval changes, `SettingsStore` posts a notification so `ClipboardMonitor` can restart its timer.

## SettingsStore

Central `@MainActor ObservableObject` defining all `@AppStorage` keys as computed properties.

| Key | Type | Default | Scope |
|-----|------|---------|-------|
| `historyMaxCount` | Int | 200 | Clipboard |
| `imageMaxSizeMB` | Int | 2 (0 = unlimited) | Clipboard |
| `pollingInterval` | Double | 0.5 | Clipboard |
| `cleanupOnStartup` | Bool | true | Clipboard |
| `dedupEnabled` | Bool | true | Clipboard |
| `showHideShortcut` | String? | nil | Shortcuts |
| `quickPasteShortcut` | String? | nil | Shortcuts |
| `togglePinShortcut` | String? | nil | Shortcuts |
| `iCloudSyncEnabled` | Bool | false | Advanced |

Also provides methods:
- `resetAll()` — clear all UserDefaults keys back to defaults
- `exportData(context:)` — serialize clip items to JSON, return Data
- `importData(_:context:)` — parse JSON, merge into context (dedup)
- `clearAllHistory(context:)` — delete all ClipItem records

## Settings Scene (Mini_CapsuleApp.swift)

```swift
Settings {
    TabView {
        ClipboardSettingsView()
            .tabItem { Label("剪贴板", systemImage: "doc.on.clipboard") }
        ShortcutsSettingsView()
            .tabItem { Label("快捷键", systemImage: "command") }
        AdvancedSettingsView()
            .tabItem { Label("高级", systemImage: "ellipsis.curlybraces") }
    }
}
.environmentObject(settingsStore)
```

Pass `ModelContainer.shared` via environment so Advanced tab can access SwiftData for export/import.

## Tab Details

### Clipboard Tab

| Setting | Control | Default | Range | Immediate |
|---------|---------|---------|-------|-----------|
| History max count | Stepper + text | 200 | 50–1000, step 50 | Yes |
| Image max size | Picker | 2 MB | 1MB / 2MB / 5MB / Unlimited | Yes |
| Polling interval | Picker | 0.5s | 0.5s / 1s / 2s | Restarts monitor |
| Cleanup on startup | Toggle | On | — | Next launch |
| Dedup content | Toggle | On | — | Yes |

Layout: `Form` with `Section { LabeledContent { ... } }` rows, matching macOS standard Settings appearance. Stepper shows "200 条" label. Picker uses `.menu` style.

### Shortcuts Tab

| Action | Default | Control |
|--------|---------|---------|
| Show/Hide capsule | ⌘⇧V | Record button |
| Quick paste latest | ⌘⇧C | Record button |
| Toggle pin | None | Record button |

Each row shows: label + current shortcut display + "录制" button. Clicking "录制" enters capture mode (visual feedback: button turns red, text shows "按下快捷键..."). On keyDown, capture the combo, validate for conflicts, and save.

Shortcut storage: serialize as string `"modifiers+keyCode"` (e.g. `"cmd+shift+V"`). Replay via `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` in `CapsuleAppDelegate`.

**Conflict warning**: when a captured shortcut matches a known system shortcut or an already-assigned Mini Capsule shortcut, show an inline warning below the row: "⚠️ 与系统快捷键冲突" or "⚠️ 与「快速粘贴」冲突".

### Advanced Tab

| Setting | Control | Behavior |
|---------|---------|----------|
| iCloud Sync | Toggle | Enables CloudKit sync (future implementation, greyed out for now with note "即将推出") |
| Export Data | Button | Opens NSSavePanel, saves JSON to chosen location |
| Import Data | Button | Opens NSOpenPanel, merges items into SwiftData (dedup by content) |
| Clear All History | Destructive Button | Shows confirmation alert, then deletes all ClipItem records |
| Reset Settings | Button | Shows confirmation alert, clears all UserDefaults keys |

Export JSON format:
```json
[
  {
    "type": "text",
    "content": "...",
    "timestamp": "2026-07-06T12:00:00Z",
    "pasteCount": 5,
    "sourceApp": "com.apple.Safari"
  }
]
```
Image items include `"fileName"` and `"data"` (base64-encoded).

Import strategy: **merge with dedup**. For text items, skip if identical content already exists. For images, skip if MD5 matches. Timestamps preserved from export.

## Wiring the Gear Button

In `CapsuleExpandedView.swift`, replace the empty gear button action:

```swift
Button(action: {
    if #available(macOS 14.0, *) {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    } else {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}) { ... }
```

Or use `SettingsLink` (macOS 14+). For compatibility with macOS 26.5 deployment target, the `openSettings` environment action can be used directly.

## Service Adaptation

### ClipboardMonitor

Replace hardcoded values with `UserDefaults` reads:
- `pollingInterval` → read from `UserDefaults.standard.double(forKey: "pollingInterval")` (min 0.5)
- `maxImageBytes` → read from `UserDefaults.standard.integer(forKey: "imageMaxSizeMB")`
- `enforceCap.maxCount` → read from `UserDefaults.standard.integer(forKey: "historyMaxCount")`

Listen for `NSNotification.Name("SettingsPollingIntervalChanged")` to restart the timer with a new interval.

### FrequencyCleanupService

- `keepCount` parameter reads from `UserDefaults.standard.integer(forKey: "historyMaxCount")`, capped at a fraction (e.g., min(50, maxCount)).

### CapsuleAppDelegate

Register keyboard shortcut handlers (`NSEvent.addLocalMonitorForEvents`) on startup based on stored shortcuts.

## Edge Cases

1. **First launch** — all UserDefaults keys are nil; SettingsStore provides defaults. Settings window shows defaults correctly.
2. **Import with empty file** — show alert "文件为空或格式不正确".
3. **Import with invalid JSON** — show alert with error description.
4. **Export with 0 items** — still allow, resulting file is an empty array `[]`.
5. **Clear history while import in progress** — disable button during operation (use `.disabled()` modifier with a `@State isOperating` flag).
6. **Duplicate shortcut assignment** — warn inline, allow but flag.
7. **Settings window already open** — `Settings` scene handles this natively (focuses existing window).
8. **Polling interval change while pasting** — timer restart is async; current paste operation completes normally.

## Testing

- **Unit tests**: `SettingsStoreTests` verifying defaults, reset, key read/write.
- **Manual verification**: open gear → settings window, change values, confirm behavior in capsule view.

## Out of Scope

- General tab (user declined)
- iCloud sync implementation (toggle shown but disabled with "coming soon" note)
- Per-application clipboard filters
- Appearance theme selection (macOS inherits system theme)
