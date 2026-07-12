# Backfill: Settings, ViewModels & Gate Flip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining feature-inventory rows (8, 9, 10, 11, 12, 13, 15, 16, 17) by backfilling the genuine gaps — `SettingsStore` side-effect notifications, export/import/clear, and model initializers — confirming the already-rich viewmodel/window/menubar suites, then **flip the meta-gate** (`requireAllCovered = true`) so any future uncovered feature fails the build.

**Architecture:** `SettingsStore` posts `NotificationCenter` events on specific setters; tests observe `.default` synchronously in a `.serialized` suite to avoid cross-talk. Export/import use in-memory SwiftData. The remaining T3/T4 features (window controller, app wiring, UI views) are already covered by the existing `Mini_CapsuleTests` controller/service tests plus the T4 manual checklist — this plan links them and turns on strict enforcement.

**Tech Stack:** Swift Testing, `SwiftData` in-memory, `NotificationCenter`, XCUITest (one smoke test).

## Global Constraints

- **Prerequisite:** Plans 1–3 landed; the coverage manifest currently has features 1,2,3,4,5,6,7,14,18 = `covered` and 8,9,10,11,12,13,15,16,17 = `pending`.
- **Deployment floor:** macOS 14.0. Xcode synchronized groups — no `project.pbxproj` edits.
- **No production behavior changes.** This plan is tests + docs + one test-constant flip only.
- **`NotificationCenter` isolation:** settings side-effect tests use a `.serialized` suite because they observe the global `.default` center.
- **Test module import:** `@testable import Mini_Capsule`.
- **Full xcodebuild path** if needed: `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild`.

---

## File Structure

**New test files (target: Mini CapsuleTests):**
- `Mini CapsuleTests/Integration/SettingsStoreSideEffectTests.swift` — notification side-effects (feature 8)
- `Mini CapsuleTests/Integration/SettingsStoreDataTests.swift` — export/import/clear (feature 8)
- `Mini CapsuleTests/Unit/ModelInitTests.swift` — `ClipItem`/`Item` initializers (feature 16)

**New UI test (target: Mini CapsuleUITests):**
- `Mini CapsuleUITests/CapsuleSmokeUITests.swift` — one launch smoke test (feature 17, runs in `full` config only)

**Modified files:**
- `Mini CapsuleTests/MetaCoverageTests.swift` — set `requireAllCovered = true`
- `docs/testing/coverage-manifest.json` + `docs/testing/traceability-matrix.md` — all features → `covered`

---

## Task 1: SettingsStore side-effect notifications (feature 8)

**Files:**
- Create: `Mini CapsuleTests/Integration/SettingsStoreSideEffectTests.swift`

**Interfaces:**
- Consumes: `SettingsStore`, `Notification.Name.shortcutsDidChange`, `.capsuleStyleDidChange`.

**Verified behavior (from `SettingsStore.swift`):** the three shortcut setters post `.shortcutsDidChange`; `collapsedStyle` and `ringDiameter` post `.capsuleStyleDidChange`; **all other setters post neither** (`pollingInterval`/`showFloatingPanel` notifications originate in the settings *views*, not the store).

- [ ] **Step 1: Write the failing test**

Create `Mini CapsuleTests/Integration/SettingsStoreSideEffectTests.swift`:

```swift
import Testing
import Foundation
@testable import Mini_Capsule

@MainActor
@Suite(.tags(.integration), .serialized)
struct SettingsStoreSideEffectTests {
    /// Count posts of `name` while running `body`, then clean up.
    private func countPosts(of name: Notification.Name, _ body: () -> Void) -> Int {
        var count = 0
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        body()
        return count
    }

    @Test func showHideShortcutPostsShortcutsDidChange() {
        #expect(countPosts(of: .shortcutsDidChange) { SettingsStore().showHideShortcut = "cmd+shift+x" } == 1)
    }

    @Test func quickPasteShortcutPostsShortcutsDidChange() {
        #expect(countPosts(of: .shortcutsDidChange) { SettingsStore().quickPasteShortcut = "cmd+shift+y" } == 1)
    }

    @Test func togglePinShortcutPostsShortcutsDidChange() {
        #expect(countPosts(of: .shortcutsDidChange) { SettingsStore().togglePinShortcut = "cmd+shift+p" } == 1)
    }

    @Test func collapsedStylePostsCapsuleStyleDidChange() {
        #expect(countPosts(of: .capsuleStyleDidChange) { SettingsStore().collapsedStyle = "dot" } == 1)
    }

    @Test func ringDiameterPostsCapsuleStyleDidChange() {
        #expect(countPosts(of: .capsuleStyleDidChange) { SettingsStore().ringDiameter = 42 } == 1)
    }

    @Test func nonSideEffectSetterPostsNothing() {
        let shortcuts = countPosts(of: .shortcutsDidChange) { SettingsStore().historyMaxCount = 999 }
        let style = countPosts(of: .capsuleStyleDidChange) { SettingsStore().dedupEnabled = false }
        #expect(shortcuts == 0)
        #expect(style == 0)
    }
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/SettingsStoreSideEffectTests" 2>&1 | tail -20`
Expected: PASS (6 tests). (Implementation already exists; these lock in the side-effect contract.)

- [ ] **Step 3: (regression lock — no production change)**

- [ ] **Step 4: Confirm green** (rerun Step 2 command).

- [ ] **Step 5: Commit**

```bash
git add "Mini CapsuleTests/Integration/SettingsStoreSideEffectTests.swift"
git commit -m "test(settings): SettingsStore notification side-effects (feature 8)"
```

---

## Task 2: SettingsStore export / import / clear (feature 8)

**Files:**
- Create: `Mini CapsuleTests/Integration/SettingsStoreDataTests.swift`

**Interfaces:**
- Consumes: `SettingsStore.exportData(context:)`, `importData(_:context:)`, `clearAllHistory(context:)`.

- [ ] **Step 1: Write the failing test**

Create `Mini CapsuleTests/Integration/SettingsStoreDataTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Mini_Capsule

@MainActor
@Suite(.tags(.integration))
struct SettingsStoreDataTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @Test func exportThenImportRoundtripsText() throws {
        let ctx = try makeContext()
        ctx.insert(ClipItem(contentTypeRaw: "text", textContent: "alpha"))
        ctx.insert(ClipItem(contentTypeRaw: "text", textContent: "beta"))
        try ctx.save()
        let store = SettingsStore()

        let blob = try #require(store.exportData(context: ctx))
        let ctx2 = try makeContext()
        try store.importData(blob, context: ctx2)

        let texts = try ctx2.fetch(FetchDescriptor<ClipItem>()).compactMap { $0.textContent }
        #expect(Set(texts) == ["alpha", "beta"])
    }

    @Test func importSkipsDuplicateText() throws {
        let ctx = try makeContext()
        ctx.insert(ClipItem(contentTypeRaw: "text", textContent: "dup"))
        try ctx.save()
        let store = SettingsStore()
        let blob = try #require(store.exportData(context: ctx))   // contains "dup"

        try store.importData(blob, context: ctx)                  // import into same context
        let count = try ctx.fetch(FetchDescriptor<ClipItem>()).filter { $0.textContent == "dup" }.count
        #expect(count == 1)                                       // not duplicated
    }

    @Test func importImageRoundtripsViaBase64() throws {
        let ctx = try makeContext()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 7, 7, 7])
        ctx.insert(ClipItem(contentTypeRaw: "image", imageData: png,
                            imageMD5: ClipboardMonitor.md5Hash(png)))
        try ctx.save()
        let store = SettingsStore()
        let blob = try #require(store.exportData(context: ctx))
        let ctx2 = try makeContext()
        try store.importData(blob, context: ctx2)

        let img = try ctx2.fetch(FetchDescriptor<ClipItem>()).first { $0.contentTypeRaw == "image" }
        #expect(img?.imageData == png)
    }

    @Test func clearAllHistoryRemovesEverything() throws {
        let ctx = try makeContext()
        for i in 0..<5 { ctx.insert(ClipItem(contentTypeRaw: "text", textContent: "t\(i)")) }
        try ctx.save()
        SettingsStore().clearAllHistory(context: ctx)
        #expect(try ctx.fetch(FetchDescriptor<ClipItem>()).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/SettingsStoreDataTests" 2>&1 | tail -20`
Expected: PASS (4 tests).

- [ ] **Step 3: (regression lock — no production change)**

- [ ] **Step 4: Confirm green** (rerun Step 2 command).

- [ ] **Step 5: Commit**

```bash
git add "Mini CapsuleTests/Integration/SettingsStoreDataTests.swift"
git commit -m "test(settings): export/import/clear roundtrip + dedup (feature 8)"
```

---

## Task 3: Model initializers (feature 16)

**Files:**
- Create: `Mini CapsuleTests/Unit/ModelInitTests.swift`

**Interfaces:**
- Consumes: `ClipItem` (init defaults verified against `Models/ClipItem.swift`), `Item`.

- [ ] **Step 1: Write the failing test**

Create `Mini CapsuleTests/Unit/ModelInitTests.swift`:

```swift
import Testing
import Foundation
@testable import Mini_Capsule

@Suite(.tags(.unit))
struct ModelInitTests {
    @Test func clipItemDefaultsAreSane() {
        let before = Date()
        let item = ClipItem(contentTypeRaw: "text")
        #expect(item.contentTypeRaw == "text")
        #expect(item.pasteCount == 0)
        #expect(item.isPinned == false)
        #expect(item.textContent == nil)
        #expect(item.imageData == nil)
        #expect(item.sortOrder == nil)
        #expect(item.lastPastedAt == nil)
        #expect(item.timestamp >= before)                 // defaults to ~now
        #expect(item.sourceAppBundleID == nil)
    }

    @Test func clipItemPreservesProvidedValues() {
        let ts = Date(timeIntervalSince1970: 1000)
        let item = ClipItem(timestamp: ts, pasteCount: 7, contentTypeRaw: "image",
                            imageData: Data([1, 2]), imageFileName: "a.png",
                            imageMD5: "abc", isPinned: true, sortOrder: 3,
                            sourceAppBundleID: "com.test")
        #expect(item.timestamp == ts)
        #expect(item.pasteCount == 7)
        #expect(item.imageFileName == "a.png")
        #expect(item.imageMD5 == "abc")
        #expect(item.isPinned)
        #expect(item.sortOrder == 3)
        #expect(item.sourceAppBundleID == "com.test")
    }

    @Test func clipItemIDsAreUnique() {
        #expect(ClipItem(contentTypeRaw: "text").id != ClipItem(contentTypeRaw: "text").id)
    }

    @Test func legacyItemStoresTimestamp() {
        let ts = Date(timeIntervalSince1970: 500)
        #expect(Item(timestamp: ts).timestamp == ts)
    }
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/ModelInitTests" 2>&1 | tail -20`
Expected: PASS (4 tests). (If `Item`'s initializer differs, open `Mini Capsule/Item.swift` and match its exact parameter — it is a single-field template model.)

- [ ] **Step 3: (regression lock — no production change)**

- [ ] **Step 4: Confirm green** (rerun Step 2 command).

- [ ] **Step 5: Commit**

```bash
git add "Mini CapsuleTests/Unit/ModelInitTests.swift"
git commit -m "test(models): ClipItem/Item initializer defaults & preservation (feature 16)"
```

---

## Task 4: UI smoke test (feature 17)

**Files:**
- Create: `Mini CapsuleUITests/CapsuleSmokeUITests.swift`

**Interfaces:** XCUITest — launches the app. Runs only in the `full` test-plan config (the UI target is disabled in `fast`).

**Note:** Mini Capsule is a menu-bar / floating-panel app with no standard main window, so deep UI assertions are fragile and belong to the T4 manual checklist (M5/M6/M9). This smoke test verifies clean launch/termination; richer flows stay manual.

- [ ] **Step 1: Write the test**

Create `Mini CapsuleUITests/CapsuleSmokeUITests.swift`:

```swift
import XCTest

final class CapsuleSmokeUITests: XCTestCase {
    func testAppLaunchesAndTerminatesCleanly() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground, "app should be running after launch")
        app.terminate()
        XCTAssertEqual(app.state, .notRunning, "app should terminate cleanly")
    }
}
```

- [ ] **Step 2: Run the UI test via the full plan**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleUITests/CapsuleSmokeUITests" 2>&1 | tail -20`
Expected: PASS. (If the UI target is not enabled for the destination, ensure the `Mini CapsuleUITests` target builds; this test lives there and runs under the `full` config.)

- [ ] **Step 3: (no production change)**

- [ ] **Step 4: Confirm green** (rerun Step 2 command).

- [ ] **Step 5: Commit**

```bash
git add "Mini CapsuleUITests/CapsuleSmokeUITests.swift"
git commit -m "test(ui): app launch/terminate smoke test (feature 17)"
```

---

## Task 5: Flip the gate — mark all features covered + enforce

**Files:**
- Modify: `docs/testing/coverage-manifest.json`
- Modify: `docs/testing/traceability-matrix.md`
- Modify: `Mini CapsuleTests/MetaCoverageTests.swift`

- [ ] **Step 1: Mark every remaining feature covered in the manifest**

In `docs/testing/coverage-manifest.json`, update features 8–13, 15, 16, 17 to `covered` with their linked tests/checklist (all others are already `covered` from Plans 1–3):

```json
    { "id": 8,  "name": "Settings (Data/Store/Persistence)","tier": ["T1","T2"],  "tests": ["SettingsDataTests","SettingsPersistenceTests","SettingsStoreSideEffectTests","SettingsStoreDataTests","Mini_CapsuleTests"], "checklist": [], "status": "covered" },
    { "id": 9,  "name": "ClipboardListViewModel",           "tier": ["T1"],       "tests": ["ClipboardListViewModelTests"], "checklist": [], "status": "covered" },
    { "id": 10, "name": "CapsuleViewModel",                 "tier": ["T1"],       "tests": ["CapsuleViewModelTests"], "checklist": [], "status": "covered" },
    { "id": 11, "name": "MenuBarService",                   "tier": ["T2","T3"],  "tests": ["MenuBarServiceTests","Mini_CapsuleTests"], "checklist": ["M9"], "status": "covered" },
    { "id": 12, "name": "FrequencyCleanupService",          "tier": ["T1"],       "tests": ["FrequencyCleanupServiceTests"], "checklist": [], "status": "covered" },
    { "id": 13, "name": "CapsuleWindowController",          "tier": ["T3","T4"],  "tests": ["Mini_CapsuleTests"], "checklist": ["M5","M6"], "status": "covered" },
    { "id": 15, "name": "App wiring / AppDelegate",         "tier": ["T3","T4"],  "tests": ["Mini_CapsuleTests"], "checklist": ["M8"], "status": "covered" },
    { "id": 16, "name": "Models (ClipItem/Item)",           "tier": ["T1"],       "tests": ["ModelInitTests"], "checklist": [], "status": "covered" },
    { "id": 17, "name": "UI views x9",                      "tier": ["T3","T4"],  "tests": ["CapsuleSmokeUITests"], "checklist": ["M5","M6","M9"], "status": "covered" }
```

- [ ] **Step 2: Mirror into the human matrix**

In `docs/testing/traceability-matrix.md`, set all rows to `covered` with the same links, and update the header note to say the gate is now enforced (`requireAllCovered = true`).

- [ ] **Step 3: Flip the enforcement switch**

In `Mini CapsuleTests/MetaCoverageTests.swift`, change:

```swift
    static let requireAllCovered = false
```

to:

```swift
    static let requireAllCovered = true
```

- [ ] **Step 4: Run the meta-gate to verify strict enforcement passes**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/MetaCoverageTests" 2>&1 | tail -20`
Expected: PASS (3 tests) — `noFeatureRemainsPending` now actively asserts every feature is `covered`. If it fails, a manifest row is still `pending`; fix the manifest.

- [ ] **Step 5: Full-suite green run (fast) + confirm no `pending` remains**

Run: `Scripts/run-tests.sh fast 2>&1 | tee /tmp/mc-plan4.log | tail -40`
Then: `grep -c '"status": "pending"' docs/testing/coverage-manifest.json`
Expected: `run-tests.sh` exits 0; the grep prints `0`.

- [ ] **Step 6: Commit**

```bash
git add docs/testing/coverage-manifest.json docs/testing/traceability-matrix.md "Mini CapsuleTests/MetaCoverageTests.swift"
git commit -m "test(meta): mark all features covered and enforce no-omissions gate"
```

---

## Task 6: Final roadmap verification

**Files:** none (verification only).

- [ ] **Step 1: Run the full plan (fast + full)**

Run: `Scripts/run-tests.sh fast 2>&1 | tail -20` — expect exit 0.
Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -testPlan MiniCapsule 2>&1 | tail -30` — expect all suites (unit, integration, meta, UI) pass.

- [ ] **Step 2: Confirm the traceability guarantee**

Run: `python3 -c "import json; d=json.load(open('docs/testing/coverage-manifest.json')); assert all(f['status']=='covered' and (f['tests'] or f['checklist']) for f in d['features']); print('all', len(d['features']), 'features covered with links')"`
Expected: `all 18 features covered with links`.

- [ ] **Step 3: Confirm archived chains exist for debugging**

Run: `ls TestResults/*/logs/*.jsonl | wc -l`
Expected: a non-zero count — full-chain logs archived per test.

- [ ] **Step 4: Final commit**

```bash
git add -A && git commit -m "test: full automated coverage roadmap complete" --allow-empty
```

---

## Self-Review Notes (author)

- **Feature 8 (Settings):** existing `SettingsDataTests`/`SettingsPersistenceTests`/`Mini_CapsuleTests` + Task 1 (side-effect notifications, verified against the real setters) + Task 2 (export/import/clear).
- **Features 9, 10:** already richly covered (20 and 10 tests) — linked, not duplicated.
- **Feature 11:** `MenuBarServiceTests` (icon) + `Mini_CapsuleTests` (toggle/showFloatingPanel) + M9 (popover interaction).
- **Feature 12:** existing `FrequencyCleanupServiceTests` (keepCount + pinned-exempt) — linked.
- **Features 13, 15:** existing `Mini_CapsuleTests` controller/service tests (corner radius, drag monitor, reset position, polling-interval read, showFloatingPanel read) + M5/M6/M8.
- **Feature 16:** Task 3 model init tests.
- **Feature 17:** Task 4 launch smoke + M5/M6/M9 manual.
- **Gate flip (Task 5):** every feature is `covered` with a test or checklist link; `requireAllCovered = true` makes `MetaCoverageTests.noFeatureRemainsPending` actively enforce it — the mechanical realization of requirement #3 ("no omissions").
- **Correctness caught during planning:** only shortcut/style/ringDiameter setters post notifications (not pollingInterval/showFloatingPanel, which post from the views) — tests assert exactly that, including the negative case.
- **Consistency:** `SettingsStore` method signatures (`exportData(context:)`, `importData(_:context:)`, `clearAllHistory(context:)`), `ClipItem` init, and `ClipboardMonitor.md5Hash` match the sources read during planning.
```
