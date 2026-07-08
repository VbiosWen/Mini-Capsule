# Phase 1: Critical + High Bug Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the one Critical and six High bugs found in the [health-check findings report](../specs/2026-07-08-app-health-check-findings.md), each behind a test, without touching dead code or refactors (those are later phases).

**Architecture:** Small, isolated fixes. Two new small units are introduced only where a fix requires it: a testable `HotKeyParser` + `HotKeyCenter` for global hotkeys (H1). Everything else is an in-place fix plus a test that reproduces the bug first.

**Tech Stack:** Swift 5, SwiftUI + AppKit + SwiftData, Carbon.HIToolbox (H1), Swift Testing (`import Testing`, `@Test`, `#expect`) for units, in-memory `ModelContainer` for data tests.

## Global Constraints

- Deployment target macOS 26.5; Swift 5 language mode. Do not raise or lower them.
- Every build/test command MUST prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and pass `CODE_SIGNING_ALLOWED=NO` (the machine's active toolchain is CommandLineTools and the target has signed entitlements).
- Unit tests use **Swift Testing** (`@Test`/`#expect`), not XCTest. Data tests build an in-memory container with `Schema([Item.self, ClipItem.self])` + `ModelConfiguration(isStoredInMemoryOnly: true)` (keep `Item.self` — dead-code removal is Phase 3).
- **Behavior-preserving except the specific bug being fixed.** No refactors, no dead-code deletion, no renames beyond what a fix requires.
- After each task: full suite must stay green. AppKit behaviors that unit tests can't cover (global hotkeys, paste, window) are flagged **MANUAL-VERIFY** and listed for the user.
- Full test command (reused everywhere below):
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" \
    -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -20
  ```

---

### Task 1: C1 — Fix `enforceCap` out-of-range crash

**Files:**
- Modify: `Mini Capsule/Services/ClipboardMonitor.swift:233-246` (make `enforceCap` internal; fix logic)
- Test: `Mini CapsuleTests/ClipboardMonitorTests.swift` (create)

**Interfaces:**
- Produces: `func enforceCap(context: ModelContext, maxCount: Int)` on `ClipboardMonitor` (was `private`, now internal for testing).

- [ ] **Step 1: Write the failing test** — reproduces the crash (many pinned items at the cap).

Create `Mini CapsuleTests/ClipboardMonitorTests.swift`:
```swift
import Testing
import Foundation
import SwiftData
@testable import Mini_Capsule

@MainActor
struct ClipboardMonitorTests {
    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func enforceCapWithPinnedItemsDoesNotCrashAndKeepsPinned() throws {
        let context = try Self.makeContainer().mainContext
        let monitor = ClipboardMonitor(settings: SettingsStore())
        // 200 items at the default cap, 5 pinned -> old code: suffix(from: 200) on 195 -> trap.
        for i in 0..<200 {
            let item = ClipItem(contentTypeRaw: "text", textContent: "t\(i)", isPinned: i < 5)
            item.pasteCount = i
            context.insert(item)
        }
        try context.save()

        monitor.enforceCap(context: context, maxCount: 200)   // must not crash

        let remaining = try context.fetch(FetchDescriptor<ClipItem>())
        #expect(remaining.filter { $0.isPinned }.count == 5)   // pinned never deleted
        #expect(remaining.count <= 200)                        // room made for the incoming item
    }

    @Test func enforceCapDeletesLeastPastedUnpinnedFirst() throws {
        let context = try Self.makeContainer().mainContext
        let monitor = ClipboardMonitor(settings: SettingsStore())
        for i in 0..<10 {
            let item = ClipItem(contentTypeRaw: "text", textContent: "t\(i)")
            item.pasteCount = i               // t0 least used, t9 most used
            context.insert(item)
        }
        try context.save()

        monitor.enforceCap(context: context, maxCount: 8)   // 10 items, cap 8 -> remove 3 to fit new one

        let remaining = try context.fetch(FetchDescriptor<ClipItem>())
        let survivingCounts = Set(remaining.map { $0.pasteCount })
        #expect(remaining.count == 7)                      // 10 - 3 removed
        #expect(!survivingCounts.contains(0))              // lowest pasteCount removed
        #expect(survivingCounts.contains(9))               // highest kept
    }
}
```

- [ ] **Step 2: Run the tests, verify they fail**

Run the full test command. Expected: `enforceCapWithPinnedItemsDoesNotCrashAndKeepsPinned` crashes/fails on the old `suffix(from:)`; the file won't even compile until `enforceCap` is internal — so expect a compile error first (`'enforceCap' is inaccessible due to 'private'`).

- [ ] **Step 3: Fix `enforceCap`** — replace `Mini Capsule/Services/ClipboardMonitor.swift:233-246` with:
```swift
    func enforceCap(context: ModelContext, maxCount: Int) {
        guard let items = try? context.fetch(FetchDescriptor<ClipItem>(sortBy: [])),
              items.count >= maxCount else { return }
        // Called before inserting the new item: remove enough to leave room for one.
        let overflow = items.count - maxCount + 1
        let deletable = items
            .filter { !$0.isPinned }
            .sorted { $0.pasteCount < $1.pasteCount }   // least-used first
        for item in deletable.prefix(overflow) {        // prefix() is safe if overflow > count
            context.delete(item)
        }
    }
```

- [ ] **Step 4: Run the tests, verify they pass**

Run the full test command. Expected: both new tests PASS; all previously-passing tests still pass.

- [ ] **Step 5: Commit**
```bash
git add "Mini Capsule/Services/ClipboardMonitor.swift" "Mini CapsuleTests/ClipboardMonitorTests.swift"
git commit -m "fix(C1): prevent enforceCap crash when pinned items exceed cap

suffix(from:) took a start index, not a count; with non-pinned items
fewer than maxCount it trapped (Range requires lowerBound <= upperBound).
Reproduced at the default 200-item cap with >=1 pinned item.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: H3 — Forward/backward-compatible settings decoding

**Files:**
- Modify: `Mini Capsule/Settings/SettingsData.swift` (add `init(from:)` in an extension)
- Test: `Mini CapsuleTests/Settings/SettingsDataTests.swift` (add a test)

**Interfaces:**
- Produces: a tolerant `SettingsData.init(from:)` — missing JSON keys fall back to per-field defaults instead of throwing. The synthesized `SettingsData()` and memberwise init are preserved (the new init lives in an extension).

- [ ] **Step 1: Write the failing test** — add to `SettingsDataTests`:
```swift
    @Test func decodePartialJSONFillsMissingKeysWithDefaults() throws {
        // Simulates an OLD settings.json written before newer fields existed.
        let partial = #"{"historyMaxCount": 99, "ringDiameter": 45}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SettingsData.self, from: partial)
        #expect(decoded.historyMaxCount == 99)          // present key preserved
        #expect(decoded.ringDiameter == 45)             // present key preserved
        #expect(decoded.pollingInterval == 0.5)         // missing -> default
        #expect(decoded.showInMenuBar == true)          // missing -> default
        #expect(decoded.dedupEnabled == true)           // missing -> default
    }
```

- [ ] **Step 2: Run the test, verify it fails**

Run the full test command. Expected: FAIL — `decode` throws `keyNotFound` (currently caught only by `load()`'s `try?`, wiping to all defaults).

- [ ] **Step 3: Add the tolerant initializer** — append to `Mini Capsule/Settings/SettingsData.swift`:
```swift

// Tolerant decoding: missing keys fall back to defaults so that adding a
// new setting in a future version does not wipe a user's existing file.
// Placed in an extension so the synthesized SettingsData() init survives.
extension SettingsData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SettingsData()
        self.init()
        historyMaxCount     = try c.decodeIfPresent(Int.self,    forKey: .historyMaxCount)     ?? d.historyMaxCount
        imageMaxSizeMB      = try c.decodeIfPresent(Int.self,    forKey: .imageMaxSizeMB)      ?? d.imageMaxSizeMB
        pollingInterval     = try c.decodeIfPresent(Double.self, forKey: .pollingInterval)     ?? d.pollingInterval
        cleanupOnStartup    = try c.decodeIfPresent(Bool.self,   forKey: .cleanupOnStartup)    ?? d.cleanupOnStartup
        dedupEnabled        = try c.decodeIfPresent(Bool.self,   forKey: .dedupEnabled)        ?? d.dedupEnabled
        showHideShortcut    = try c.decodeIfPresent(String.self, forKey: .showHideShortcut)    ?? d.showHideShortcut
        quickPasteShortcut  = try c.decodeIfPresent(String.self, forKey: .quickPasteShortcut)  ?? d.quickPasteShortcut
        togglePinShortcut   = try c.decodeIfPresent(String.self, forKey: .togglePinShortcut)   ?? d.togglePinShortcut
        iCloudSyncEnabled   = try c.decodeIfPresent(Bool.self,   forKey: .iCloudSyncEnabled)   ?? d.iCloudSyncEnabled
        launchAtLogin       = try c.decodeIfPresent(Bool.self,   forKey: .launchAtLogin)       ?? d.launchAtLogin
        showInMenuBar       = try c.decodeIfPresent(Bool.self,   forKey: .showInMenuBar)       ?? d.showInMenuBar
        showFloatingPanel   = try c.decodeIfPresent(Bool.self,   forKey: .showFloatingPanel)   ?? d.showFloatingPanel
        collapsedStyle      = try c.decodeIfPresent(String.self, forKey: .collapsedStyle)      ?? d.collapsedStyle
        hoverExpandDelay    = try c.decodeIfPresent(Double.self, forKey: .hoverExpandDelay)    ?? d.hoverExpandDelay
        hoverCollapseDelay  = try c.decodeIfPresent(Double.self, forKey: .hoverCollapseDelay)  ?? d.hoverCollapseDelay
        panelOpacityUnfocused = try c.decodeIfPresent(Double.self, forKey: .panelOpacityUnfocused) ?? d.panelOpacityUnfocused
        backgroundImageData = try c.decodeIfPresent(Data.self,   forKey: .backgroundImageData) ?? d.backgroundImageData
        ringDiameter        = try c.decodeIfPresent(Double.self, forKey: .ringDiameter)        ?? d.ringDiameter
        capsuleWindowFrame  = try c.decodeIfPresent(Data.self,   forKey: .capsuleWindowFrame)  ?? d.capsuleWindowFrame
    }
}
```
> Note: `CodingKeys` and `encode(to:)` remain compiler-synthesized. If the build reports `CodingKeys` inaccessible, add an explicit `enum CodingKeys: String, CodingKey { case <all 19 property names> }` inside the extension.

- [ ] **Step 4: Run the test, verify it passes**

Run the full test command. Expected: new test PASSES; existing `SettingsDataTests` (roundtrip, defaults, equatable) still pass.

- [ ] **Step 5: Commit**
```bash
git add "Mini Capsule/Settings/SettingsData.swift" "Mini CapsuleTests/Settings/SettingsDataTests.swift"
git commit -m "fix(H3): tolerate missing keys when decoding SettingsData

Synthesized Decodable ignores property defaults and throws keyNotFound
on any missing key, so load() reset ALL settings to defaults whenever a
new field shipped. Custom init(from:) merges present keys over defaults.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: H2 — Default shortcuts must match the (lowercased) matcher

**Files:**
- Modify: `Mini Capsule/Settings/SettingsData.swift:15-16` (lowercase the two defaults)
- Modify: `Mini CapsuleTests/Settings/SettingsDataTests.swift:18-19` (update assertions)

- [ ] **Step 1: Update the existing test to the intended (lowercase) values** — change `SettingsDataTests.defaultValuesAreCorrect` lines 18-19:
```swift
        #expect(data.showHideShortcut == "cmd+shift+v")
        #expect(data.quickPasteShortcut == "cmd+shift+c")
```

- [ ] **Step 2: Run the test, verify it fails**

Run the full test command. Expected: FAIL — defaults are still uppercase `"cmd+shift+V"`/`"cmd+shift+C"`.

- [ ] **Step 3: Lowercase the defaults** — `Mini Capsule/Settings/SettingsData.swift:15-16`:
```swift
    var showHideShortcut: String = "cmd+shift+v"
    var quickPasteShortcut: String = "cmd+shift+c"
```

- [ ] **Step 4: Run the test, verify it passes**

Run the full test command. Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add "Mini Capsule/Settings/SettingsData.swift" "Mini CapsuleTests/Settings/SettingsDataTests.swift"
git commit -m "fix(H2): store default shortcuts lowercase to match the matcher

The event matcher lowercases the key (charactersIgnoringModifiers?
.lowercased()), so uppercase defaults 'cmd+shift+V'/'C' never matched
and the factory shortcuts never fired.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: H5 — Startup cleanup must honor `historyMaxCount`, not a hardcoded 50

**Files:**
- Modify: `Mini Capsule/Services/FrequencyCleanupService.swift:11-14` (fix keep-count derivation)
- Modify: `Mini Capsule/Mini_CapsuleApp.swift:47-51` (stop passing `keepCount: 50`)
- Test: `Mini CapsuleTests/FrequencyCleanupServiceTests.swift` (create)

**Interfaces:**
- Consumes: `SettingsProtocol.historyMaxCount`.
- Produces: `FrequencyCleanupService.performCleanup(context:keepCount:settings:)` where, when `keepCount == nil`, the keep count is `settings.historyMaxCount` (floored at 1).

- [ ] **Step 1: Write the failing test** — create `Mini CapsuleTests/FrequencyCleanupServiceTests.swift`:
```swift
import Testing
import Foundation
import SwiftData
@testable import Mini_Capsule

@MainActor
struct FrequencyCleanupServiceTests {
    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func keepCountFollowsHistoryMaxCountNotHardcoded50() throws {
        let context = try Self.makeContainer().mainContext
        let settings = SettingsStore()
        settings.historyMaxCount = 120                      // > 50 on purpose
        for i in 0..<200 {
            let item = ClipItem(contentTypeRaw: "text", textContent: "t\(i)")
            item.pasteCount = i
            context.insert(item)
        }
        try context.save()

        FrequencyCleanupService.performCleanup(context: context, keepCount: nil, settings: settings)

        let remaining = try context.fetch(FetchDescriptor<ClipItem>())
        #expect(remaining.count == 120)                    // not 50
        settings.resetAll()
    }

    @Test func pinnedItemsAreExemptFromCleanup() throws {
        let context = try Self.makeContainer().mainContext
        let settings = SettingsStore()
        settings.historyMaxCount = 5
        for i in 0..<20 {
            let item = ClipItem(contentTypeRaw: "text", textContent: "t\(i)", isPinned: i < 8)
            item.pasteCount = i
            context.insert(item)
        }
        try context.save()

        FrequencyCleanupService.performCleanup(context: context, keepCount: nil, settings: settings)

        let remaining = try context.fetch(FetchDescriptor<ClipItem>())
        #expect(remaining.filter { $0.isPinned }.count == 8)   // all pins survive even beyond keep
        settings.resetAll()
    }
}
```

- [ ] **Step 2: Run the tests, verify they fail**

Run the full test command. Expected: `keepCountFollowsHistoryMaxCountNotHardcoded50` FAILS (only 50 remain).

- [ ] **Step 3: Fix the keep-count derivation** — replace `Mini Capsule/Services/FrequencyCleanupService.swift:11-14`:
```swift
        let keep = keepCount ?? max(settings?.historyMaxCount ?? 200, 1)
```

- [ ] **Step 4: Stop hardcoding 50 at the call site** — `Mini Capsule/Mini_CapsuleApp.swift:47-51`, change `keepCount: 50` to `keepCount: nil`:
```swift
        FrequencyCleanupService.performCleanup(
            context: Self.sharedModelContainer.mainContext,
            keepCount: nil,
            settings: settingsStore
        )
```

- [ ] **Step 5: Run the tests, verify they pass**

Run the full test command. Expected: both new tests PASS; suite green.

- [ ] **Step 6: Commit**
```bash
git add "Mini Capsule/Services/FrequencyCleanupService.swift" "Mini Capsule/Mini_CapsuleApp.swift" "Mini CapsuleTests/FrequencyCleanupServiceTests.swift"
git commit -m "fix(H5): startup cleanup honors historyMaxCount instead of always 50

'count >= 50 ? min(50,count) : 50' always evaluated to 50, and the call
site hardcoded keepCount: 50, so history was trimmed to 50 on every
launch regardless of the user's setting (silent data loss).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: H6 — Respect the "cleanup on startup" toggle

**Files:**
- Modify: `Mini Capsule/Mini_CapsuleApp.swift:45-51` (guard on `cleanupOnStartup`)

**Interfaces:**
- Consumes: `settingsStore.cleanupOnStartup`.

> Note: `finishSetup` runs inside `NSApplicationDelegate` and is not unit-testable headlessly; this one-line guard is verified by inspection + MANUAL-VERIFY. The cleanup logic itself is covered by Task 4.

- [ ] **Step 1: Add the guard** — in `Mini Capsule/Mini_CapsuleApp.swift`, wrap the cleanup call in `finishSetup`:
```swift
        // Frequency cleanup on startup (only if enabled)
        if settingsStore.cleanupOnStartup {
            FrequencyCleanupService.performCleanup(
                context: Self.sharedModelContainer.mainContext,
                keepCount: nil,
                settings: settingsStore
            )
        }
```

- [ ] **Step 2: Verify build + full suite still green**

Run the full test command. Expected: `BUILD SUCCEEDED`, all tests pass (no behavior change to tested units).

- [ ] **Step 3: Commit**
```bash
git add "Mini Capsule/Mini_CapsuleApp.swift"
git commit -m "fix(H6): honor cleanupOnStartup toggle in finishSetup

finishSetup previously ran FrequencyCleanupService unconditionally,
ignoring the user's 'cleanup on startup' setting.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

**MANUAL-VERIFY (H5+H6):** Set history max to a large value, copy >50 items, disable "startup cleanup", relaunch → all items remain. Enable it, relaunch → trimmed to the configured max (pins kept).

---

### Task 6: H4 — Stop re-capturing our own clipboard writes (duplicate entries)

**Files:**
- Modify: `Mini Capsule/Services/PasteService.swift` (replace boolean `isSelfPaste` with a change-count token + helpers)
- Modify: `Mini Capsule/Services/ClipboardMonitor.swift:80` (use the token check)
- Modify: `Mini CapsuleTests/PasteServiceTests.swift` (replace the weak `isSelfPasteDefaultsToFalse` test)

**Interfaces:**
- Produces on `PasteService`:
  - `static func markSelfPaste()` — records `NSPasteboard.general.changeCount` as suppressed.
  - `static func shouldSuppress(changeCount: Int) -> Bool` — true (and consumes) if the given count is the suppressed one.
  - removes `static var isSelfPaste`.

- [ ] **Step 1: Grep for all `isSelfPaste` references** (must be exactly 3 sites before editing):
```bash
grep -rn "isSelfPaste" "Mini Capsule" "Mini CapsuleTests"
```
Expected: `PasteService.swift` (declaration + 2 set sites in copyToClipboard/paste), `ClipboardMonitor.swift:80`, and `PasteServiceTests.swift`. If more appear, update them too.

- [ ] **Step 2: Write the failing test** — replace `isSelfPasteDefaultsToFalse` in `Mini CapsuleTests/PasteServiceTests.swift` with:
```swift
    @MainActor
    @Test func copyToClipboardArmsSuppressionForItsOwnChange() {
        let item = ClipItem(contentTypeRaw: "text", textContent: "self-paste-\(UUID())")
        PasteService.copyToClipboard(item)
        let count = NSPasteboard.general.changeCount
        // The change we just made is suppressed exactly once, then released.
        #expect(PasteService.shouldSuppress(changeCount: count) == true)
        #expect(PasteService.shouldSuppress(changeCount: count) == false)
    }
```
Add `import AppKit` at the top of the test file if not present.

- [ ] **Step 3: Run the test, verify it fails**

Run the full test command. Expected: compile error (`shouldSuppress`/`copyToClipboard` token API doesn't exist yet).

- [ ] **Step 4: Replace the boolean with a change-count token** — in `Mini Capsule/Services/PasteService.swift`:

Replace `static var isSelfPaste = false` with:
```swift
    /// The pasteboard changeCount produced by our own copy/paste, so the
    /// monitor can skip exactly that change even though it polls asynchronously.
    private static var suppressedChangeCount: Int?

    static func markSelfPaste() {
        suppressedChangeCount = NSPasteboard.general.changeCount
    }

    /// Returns true (and consumes the token) when `changeCount` is the change we produced.
    static func shouldSuppress(changeCount: Int) -> Bool {
        if suppressedChangeCount == changeCount {
            suppressedChangeCount = nil
            return true
        }
        return false
    }
```

In `copyToClipboard(_:)`: remove `isSelfPaste = true` / `defer { isSelfPaste = false }`; after the `switch` that writes the pasteboard, add:
```swift
        markSelfPaste()
```

In `paste(_:context:)`: remove `isSelfPaste = true` / `defer { isSelfPaste = false }`; after the pasteboard `switch` (before simulating Cmd+V), add `markSelfPaste()`.

- [ ] **Step 5: Update the monitor's skip check** — `Mini Capsule/Services/ClipboardMonitor.swift`, replace lines 79-80:
```swift
        // Skip changes we produced ourselves (copy/paste), even across the poll gap.
        if PasteService.shouldSuppress(changeCount: currentChangeCount) { return }
```
(`lastChangeCount` was already set to `currentChangeCount` just above at line 77, so the next poll won't reprocess.)

- [ ] **Step 6: Run the tests, verify they pass**

Run the full test command. Expected: new test PASSES; suite green.

- [ ] **Step 7: Commit**
```bash
git add "Mini Capsule/Services/PasteService.swift" "Mini Capsule/Services/ClipboardMonitor.swift" "Mini CapsuleTests/PasteServiceTests.swift"
git commit -m "fix(H4): suppress self-writes by changeCount, not a sync boolean

isSelfPaste was reset synchronously but the monitor reads it only on its
async 0.5s poll, so copying/pasting an older item re-captured it as a
duplicate. Track the changeCount we produce and skip exactly that change.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

**MANUAL-VERIFY (H4):** With dedup off, click an older history item (or trigger quick-paste) → it moves/copies without creating a duplicate row on the next poll.

---

### Task 7: H1 — Global hotkeys via Carbon `RegisterEventHotKey`

**Files:**
- Create: `Mini Capsule/Services/HotKeyCenter.swift` (`HotKeyParser` + `HotKeyCenter`)
- Modify: `Mini Capsule/Mini_CapsuleApp.swift` (replace local-monitor matcher with `HotKeyCenter`; re-register on change)
- Modify: `Mini Capsule/Settings/SettingsStore.swift` (post `.shortcutsDidChange` from the 3 shortcut setters)
- Modify: `Mini Capsule/Settings/NotificationNames.swift` (add `.shortcutsDidChange`)
- Test: `Mini CapsuleTests/HotKeyParserTests.swift` (create)

**Interfaces:**
- Produces:
  - `enum HotKeyParser { static func parse(_ shortcut: String) -> (keyCode: UInt32, modifiers: UInt32)? ; static func keyCode(for character: Character) -> UInt32? }`
  - `final class HotKeyCenter { func installHandlerIfNeeded(); func register(_ shortcut: String, action: @escaping () -> Void); func unregisterAll() }`
  - `Notification.Name.shortcutsDidChange`

- [ ] **Step 1: Write the failing parser test** — create `Mini CapsuleTests/HotKeyParserTests.swift`:
```swift
import Testing
import Carbon.HIToolbox
@testable import Mini_Capsule

struct HotKeyParserTests {
    @Test func parsesModifiersAndKey() {
        let r = HotKeyParser.parse("cmd+shift+v")
        #expect(r != nil)
        #expect(r?.keyCode == UInt32(kVK_ANSI_V))            // 9
        #expect(r?.modifiers == UInt32(cmdKey | shiftKey))
    }

    @Test func isCaseInsensitiveOnKey() {
        #expect(HotKeyParser.parse("cmd+shift+V")?.keyCode == HotKeyParser.parse("cmd+shift+v")?.keyCode)
    }

    @Test func returnsNilWhenNoBaseKey() {
        #expect(HotKeyParser.parse("cmd+shift") == nil)
        #expect(HotKeyParser.parse("") == nil)
    }

    @Test func parsesControlOptionAliases() {
        let r = HotKeyParser.parse("control+option+c")
        #expect(r?.modifiers == UInt32(controlKey | optionKey))
        #expect(r?.keyCode == UInt32(kVK_ANSI_C))            // 8
    }
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run the full test command. Expected: compile error (`HotKeyParser` undefined).

- [ ] **Step 3: Create `HotKeyParser` + `HotKeyCenter`** — create `Mini Capsule/Services/HotKeyCenter.swift`:
```swift
import AppKit
import Carbon.HIToolbox

/// Parses a stored shortcut string ("cmd+shift+v") into a Carbon keyCode + modifier mask.
enum HotKeyParser {
    static func parse(_ shortcut: String) -> (keyCode: UInt32, modifiers: UInt32)? {
        let parts = shortcut.lowercased().split(separator: "+").map(String.init)
        var modifiers: UInt32 = 0
        var keyChar: Character?
        for part in parts {
            switch part {
            case "cmd", "command":     modifiers |= UInt32(cmdKey)
            case "shift":              modifiers |= UInt32(shiftKey)
            case "option", "opt", "alt": modifiers |= UInt32(optionKey)
            case "control", "ctrl":    modifiers |= UInt32(controlKey)
            default:                   keyChar = part.first   // last non-modifier wins
            }
        }
        guard let ch = keyChar, let code = keyCode(for: ch) else { return nil }
        return (code, modifiers)
    }

    /// ANSI virtual key codes for the characters used by shortcuts (a–z, 0–9).
    static func keyCode(for character: Character) -> UInt32? {
        let lower = Character(character.lowercased())
        return table[lower]
    }

    private static let table: [Character: UInt32] = [
        "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C),
        "d": UInt32(kVK_ANSI_D), "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F),
        "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H), "i": UInt32(kVK_ANSI_I),
        "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
        "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O),
        "p": UInt32(kVK_ANSI_P), "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R),
        "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T), "u": UInt32(kVK_ANSI_U),
        "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
        "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9),
    ]
}

/// Registers system-wide hotkeys with Carbon. RegisterEventHotKey consumes the
/// keystroke and needs no Input-Monitoring permission. Main-thread only.
@MainActor
final class HotKeyCenter {
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 1
    private static let signature: OSType = 0x4D435053 // 'MCPS'

    func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let this = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers on the main thread; hop to the main actor explicitly.
            MainActor.assumeIsolated { center.actions[hkID.id]?() }
            return noErr
        }, 1, &spec, this, &handler)
    }

    func register(_ shortcut: String, action: @escaping () -> Void) {
        guard let (keyCode, modifiers) = HotKeyParser.parse(shortcut) else { return }
        let id = nextID; nextID += 1
        let hkID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs.append(ref); actions[id] = action }
    }

    func unregisterAll() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll(); actions.removeAll()
    }

    deinit {
        for ref in refs { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
```

- [ ] **Step 4: Run the parser tests, verify they pass**

Run the full test command. Expected: all `HotKeyParserTests` PASS; build succeeds.

- [ ] **Step 5: Add the `.shortcutsDidChange` notification** — in `Mini Capsule/Settings/NotificationNames.swift`, add alongside the other settings names:
```swift
    static let shortcutsDidChange = Notification.Name("SettingsShortcutsDidChange")
```
Then in `Mini Capsule/Settings/SettingsStore.swift`, in each of the three shortcut setters (`showHideShortcut`, `quickPasteShortcut`, `togglePinShortcut`), add after `persist()`:
```swift
            NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
```

- [ ] **Step 6: Swap the matcher in the app delegate** — in `Mini Capsule/Mini_CapsuleApp.swift`:

Remove `private var shortcutMonitor: Any?` and the `deinit { if let monitor = shortcutMonitor { NSEvent.removeMonitor(monitor) } }`. Add a stored property:
```swift
    private let hotKeyCenter = HotKeyCenter()
```
Replace `registerShortcuts()` and delete `shortcutString(from:)`:
```swift
    private func registerShortcuts() {
        hotKeyCenter.installHandlerIfNeeded()
        hotKeyCenter.unregisterAll()
        hotKeyCenter.register(settingsStore.showHideShortcut) { [weak self] in
            self?.capsuleWindowController?.toggleWindow()
        }
        hotKeyCenter.register(settingsStore.quickPasteShortcut) { [weak self] in
            self?.performQuickPaste()
        }
        if !settingsStore.togglePinShortcut.isEmpty {
            hotKeyCenter.register(settingsStore.togglePinShortcut) { [weak self] in
                self?.performTogglePin()
            }
        }
    }
```
In `finishSetup()`, after the existing `registerShortcuts()` call, observe changes:
```swift
        NotificationCenter.default.addObserver(
            forName: .shortcutsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.registerShortcuts()
        }
```

- [ ] **Step 7: Verify build + full suite green**

Run the full test command. Expected: `BUILD SUCCEEDED`; all tests pass (parser covered; registration is runtime-only).

- [ ] **Step 8: Commit**
```bash
git add "Mini Capsule/Services/HotKeyCenter.swift" "Mini Capsule/Mini_CapsuleApp.swift" "Mini Capsule/Settings/SettingsStore.swift" "Mini Capsule/Settings/NotificationNames.swift" "Mini CapsuleTests/HotKeyParserTests.swift"
git commit -m "fix(H1): register global hotkeys via Carbon RegisterEventHotKey

Shortcuts used addLocalMonitorForEvents, which only fires when this
.accessory app is frontmost, so global show/hide, quick-paste and
toggle-pin never worked from other apps. Carbon hotkeys are system-wide,
consume the keystroke, and need no Input-Monitoring permission. Re-register
on .shortcutsDidChange.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

**MANUAL-VERIFY (H1):** With another app frontmost, press the show/hide shortcut → the capsule toggles. Change the shortcut in Settings → the new combo works immediately, the old one no longer fires.

---

## Final verification (after all tasks)

- [ ] Run the full test command once more — all suites green (baseline was 71 tests; this plan adds ~10).
- [ ] Run a plain `build` (no test) to confirm release-shaped compile:
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
  ```
- [ ] Hand the four MANUAL-VERIFY checks (H1, H4, H5+H6) to the user for on-device confirmation.
- [ ] Then proceed to Phase 2 (behavior-preserving refactors) via a new plan.

## Self-Review Notes

- **Spec coverage:** C1 (Task 1), H1 (Task 7), H2 (Task 3), H3 (Task 2), H4 (Task 6), H5 (Task 4), H6 (Task 5) — all seven Phase-1 items mapped.
- **Not in scope (by design):** M1 off-by-one is partially addressed by C1's `+1` room-making; full capacity-service unification, dead-code removal, and the `.xcodeproj` duplicate-source fix are Phase 2/3.
- **Type consistency:** `enforceCap(context:maxCount:)`, `performCleanup(context:keepCount:settings:)`, `PasteService.markSelfPaste()/shouldSuppress(changeCount:)`, `HotKeyParser.parse(_:)`, `HotKeyCenter.register(_:action:)`, `.shortcutsDidChange` are referenced consistently across tasks.
