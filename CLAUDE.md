# CLAUDE.md

Claude Code guidance for the Mini Capsule repository.

## Build & Test Commands

```bash
# macOS build (primary target)
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build

# iOS simulator build
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' build

# Run unit tests (Swift Testing framework)
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test

# Run a single test
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:Mini_CapsuleTests/ClipboardMonitorTests/nsImageToPNGDataProducesValidPNG test

# Open in Xcode
open "Mini Capsule.xcodeproj"
```

## Project Identity

Mini Capsule is a **macOS clipboard manager** with a floating capsule UI. It polls `NSPasteboard.general`, stores history in SwiftData, and provides quick paste via Carbon global hotkeys. iOS/visionOS targets exist as stubs — real functionality is macOS-only (`#if os(macOS)`).

- **Architecture:** MVVM + Services, SwiftUI with AppKit window host
- **Persistence:** SwiftData (schema: `ClipItem`, `Item`)
- **Pasteboard polling:** `Timer`-driven `NSPasteboard.changeCount` diff
- **Global hotkeys:** Carbon `RegisterEventHotKey`
- **Settings:** JSON file via `SettingsPersistence` actor, runtime via `SettingsStore`
- **Tests:** Swift Testing (`@Test`, `#expect`) for unit; XCTest for UI
- **Deployment target:** 26.5 (iOS, macOS, visionOS)

## Component Map

```
Mini_CapsuleApp.swift (App entry + CapsuleAppDelegate)
├── SettingsStore ── SettingsPersistence ── SettingsData
├── CapsuleWindowController
│   └── CapsulePanel (NSPanel, canBecomeKey=true)
│       └── CapsuleView (SwiftUI root)
│           ├── CapsuleCollapsedView   ← hover → expands
│           └── CapsuleExpandedView    ← 280×360 panel
│               ├── KeyboardEventHandler (↑↓ Enter Esc)
│               ├── ClipItemRow ×N (hover popover + contextMenu)
│               │   └── PopoverEditorView (edit text)
│               └── CopyFeedbackView ("已复制" toast)
├── ClipboardMonitor (Timer → NSPasteboard.poll)
│   └── PasteService (static: copy/paste + CGEvent Cmd+V)
├── HotKeyCenter (Carbon global hotkeys)
├── MenuBarService (NSStatusItem + NSMenu)
└── FrequencyCleanupService (startup cleanup)
```

## Key Patterns

### Settings: Protocol + Store + Persistence
- `SettingsProtocol` — protocol all consumers depend on (enables test mocking with `MockSettings`)
- `SettingsStore` — `@Observable @MainActor` class, computed props forward to `SettingsData`, `persist()` on every set, posts `NotificationCenter` for side effects (shortcuts, style, polling interval)
- `SettingsPersistence` — `actor` that reads/writes JSON to disk
- Settings views use `@Environment(SettingsStore.self)`, not a Singleton

### Clipboard Monitor: Polling with Self-Suppression
- `ClipboardMonitor` polls `NSPasteboard.general.changeCount` on a configurable `Timer`
- On change → `readPasteboard()` (layered: 7 known UTIs → NSImage fallback → fileURL → string)
- `PasteService.markSelfPaste()` sets a token; `shouldSuppress(changeCount:)` consumes it — prevents self-triggered copies from being re-captured
- MD5 dedup for images; content dedup for text (only against the latest item)

### Image Pasteboard: Layered Reading (2026-07-08)
- Priority 1: raw data from 7 known UTIs (png, tiff, jpeg, gif, heic, heif, bmp) — preserves original format, GIF animation intact
- Priority 2: `readObjects(forClasses: [NSImage.self])` fallback — covers WeChat custom types, converts to PNG
- Priority 3/4: fileURL → string
- `nsImageToPNGData()`: NSImage → TIFF → NSBitmapImageRep → PNG (fallback only)
- `capImageSize()`: resizes+recompresses to JPEG if over limit (same for all paths)

### Floating Window + Drag
- `CapsulePanel` is an `NSPanel` with `.floating`, `.nonactivatingPanel`, `.canJoinAllSpaces`
- Drag: local `NSEvent` monitor on `.leftMouseDown/Dragged/Up`, 0.5s primer before drag activates
- Frame persisted as JSON in `settingsStore.capsuleWindowFrame`

### Hover Expand/Collapse State Machine
- `CapsuleViewModel` manages: `onHoverEnter()` → delay → expand (spring animation) → post `.capsuleDidChangeExpanded`
- `CapsuleWindowController.observeExpandedState()` animates the NSWindow frame resize with corner radius changes
- `isExpandingReady` gates keyboard navigation to prevent accidental input during animation

### Inter-Component Communication: NotificationCenter
All cross-component events use `Notification.Name` extensions (defined in `NotificationNames.swift`):

| Notification | Sender → Consumer |
|---|---|
| `.pollingIntervalDidChange` | Settings → ClipboardMonitor |
| `.showFloatingPanelChanged` | Settings → CapsuleWindowController, MenuBarService |
| `.capsuleDidChangeExpanded` | CapsuleViewModel → CapsuleWindowController |
| `.capsuleStyleDidChange` | SettingsStore → CapsuleWindowController |
| `.shortcutsDidChange` | SettingsStore → CapsuleAppDelegate |
| `.capsuleDragStarted/Ended` | CapsuleWindowController → CapsuleView |
| `.capsuleDidResignKey` | CapsuleWindowController → CapsuleView |
| `.capsuleEscapePressed` | KeyboardEventHandler → CapsuleExpandedView |
| `.editTextItem` | PopoverEditorView → CapsuleExpandedView |
| `.pasteItemToFront` | ClipItemRow contextMenu → CapsuleExpandedView |
| `.togglePinItem` | ClipItemRow contextMenu → CapsuleExpandedView |

### Paste: CGEvent Simulation
- `PasteService.paste()`: writes to NSPasteboard → `markSelfPaste()` → post `CGEvent` Cmd+V
- Requires Accessibility permissions (`AXIsProcessTrustedWithOptions`)
- `keyCodeForV()` dynamically resolves V key for non-QWERTY keyboards via TIS/UCKeyTranslate

## Data Model

### ClipItem (core — `@Model`)
| Field | Type | Purpose |
|-------|------|---------|
| `id` | UUID | primary key |
| `timestamp` | Date | last capture/copy time |
| `lastPastedAt`, `pasteCount` | Date?, Int | usage stats for cleanup |
| `contentTypeRaw` | String | "text", "image", "file" |
| `textContent` | String? | text body |
| `imageData` | Data? | raw image bytes (PNG/GIF/etc.) |
| `imageFileName`, `imageMD5` | String?, String? | dedup + display name |
| `fileBookmarks` | Data? | NSURL bookmark for file refs |
| `isPinned`, `sortOrder` | Bool, Int? | pinning with manual ordering |
| `sourceAppBundleID` | String? | originating app |

### Item (legacy template — `@Model`)
Single field `timestamp: Date`. Leftover from Xcode template, not used in clipboard features.

## Testing

- **Unit tests:** Swift Testing (`import Testing`, `@Test`, `#expect`). Test files: `*Tests.swift`.
- **UI tests:** XCTest in `Mini_CapsuleUITests/`.
- **Test mocks:** `SettingsProtocol` enables injection. Create a `MockSettings` class conforming to `SettingsProtocol` — see existing pattern in `ClipboardMonitorTests.swift`.
- **SwiftData in tests:** Use `ModelConfiguration(isStoredInMemoryOnly: true)`. Register both `Item` and `ClipItem` in the test schema.
- **No xcodebuild in PATH:** Use full path `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild` if CommandLineTools is the active developer directory.

## File Index

| File | Purpose |
|------|---------|
| `Mini_CapsuleApp.swift` | App entry, CapsuleAppDelegate, wiring |
| `ContentView.swift` | iOS/visionOS stub |
| `Models/ClipItem.swift` | Core @Model entity |
| `Models/Item.swift` | Legacy template model |
| `Services/ClipboardMonitor.swift` | Pasteboard polling + image capture |
| `Services/PasteService.swift` | Copy to pasteboard + CGEvent paste |
| `Services/HotKeyCenter.swift` | Carbon global hotkeys |
| `Services/FrequencyCleanupService.swift` | Startup history cleanup |
| `Services/MenuBarService.swift` | NSStatusItem with recent items menu |
| `UI/CapsuleView.swift` | Root SwiftUI view |
| `UI/CapsuleCollapsedView.swift` | Collapsed: dot/icon/capsule |
| `UI/CapsuleExpandedView.swift` | Expanded: search + filter + list |
| `UI/CapsuleViewModel.swift` | Hover/drag/capture state machine |
| `UI/CapsuleWindowController.swift` | NSPanel + NSWindow management |
| `UI/ClipboardListViewModel.swift` | Filter, CRUD, keyboard nav |
| `UI/ClipItemRow.swift` | Single row with popover + context menu |
| `UI/KeyboardEventHandler.swift` | NSViewRepresentable for key events |
| `UI/PopoverEditorView.swift` | Inline text editor popover |
| `UI/CopyFeedbackView.swift` | "已复制" toast |
| `Settings/SettingsData.swift` | Codable struct with defaults |
| `Settings/SettingsProtocol.swift` | Protocol for DI/testing |
| `Settings/SettingsPersistence.swift` | Actor-based JSON persistence |
| `Settings/SettingsStore.swift` | @Observable runtime + side effects |
| `Settings/NotificationNames.swift` | All Notification.Name extensions |
| `Settings/GeneralSettingsView.swift` | General settings tab |
| `Settings/ClipboardSettingsView.swift` | Clipboard settings tab |
| `Settings/AppearanceSettingsView.swift` | Appearance settings tab |
| `Settings/ShortcutsSettingsView.swift` | Shortcut recording tab |
| `Settings/AdvancedSettingsView.swift` | Import/export tab |
| `Utilities/ColorHex.swift` | Color ↔ hex |

## Full symbol table: `docs/superpowers/symbol-table.md`
