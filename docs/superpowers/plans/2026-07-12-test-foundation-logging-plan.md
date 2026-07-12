# Testing Foundation & Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the app-level structured logging system and the entire automated-test harness (tiers, runner, per-failure log archival, traceability gate) **without yet changing any app service** — a self-contained, all-green foundation that later plans build tests on top of.

**Architecture:** A small logging façade (`Log`) fans out `LogEvent`s to pluggable `LogSink`s: `OSLogSink` (os.Logger → Console.app), `FileSink` (JSONL archive), and a test-only `InMemoryLogSink`. A `.xctestplan` splits tests into fast (Unit+Integration) and full (+UI) configs. `run-tests.sh` runs the plan, archives each test's log chain, promotes failing tests' chains into `failures/`, checks a scoped coverage gate, and validates a machine-readable coverage manifest whose meta-check test enforces "every feature is covered by a test or a checklist item."

**Tech Stack:** Swift 5.9+/Swift Testing (`import Testing`), `os.Logger`, `Foundation`, `xcodebuild`, `xcrun xcresulttool`/`xccov`, bash, GitHub Actions (macOS runner).

## Global Constraints

- **Deployment floor:** macOS 14.0 (iOS/visionOS stubs unchanged). Use only APIs available on macOS 14.
- **Xcode project model:** `objectVersion = 77` with file-system-synchronized groups — new files placed under `Mini Capsule/` or `Mini CapsuleTests/` are auto-included in their target; **no `project.pbxproj` edits required.**
- **Test framework:** Swift Testing (`@Test`, `@Suite`, `#expect`, `#require`, `@Tag`) for unit/integration. Do **not** convert existing XCTest UI tests.
- **Privacy rule (non-negotiable):** logging code must never place clipboard content (text bodies, image bytes, file contents) into `LogEvent.message` or `LogEvent.metadata`. Only lengths, types, counts, ids, md5 prefixes.
- **Behavior preservation:** this plan adds files only; it must not alter any runtime behavior of existing services. The pre-existing 104 tests must stay green after every task.
- **Module name:** the test target imports the app as `@testable import Mini_Capsule`.
- **Full xcodebuild path** (CommandLineTools may be active): `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild`. Commands below use `xcodebuild`; substitute the full path if it is not on PATH.

---

## File Structure

**New app files (target: Mini Capsule):**
- `Mini Capsule/Logging/LogEvent.swift` — `LogCategory`, `LogLevel`, `LogEvent` (Codable value types)
- `Mini Capsule/Logging/LogSink.swift` — `LogSink` protocol, `Log` façade, ergonomic `log(...)` extension
- `Mini Capsule/Logging/OSLogSink.swift` — os.Logger-backed sink + pure `formatLine` formatter
- `Mini Capsule/Logging/FileSink.swift` — JSONL append sink with size rotation

**New test files (target: Mini CapsuleTests):**
- `Mini CapsuleTests/Support/InMemoryLogSink.swift` — in-memory sink for assertions
- `Mini CapsuleTests/Support/LogArchive.swift` — helper that archives a sink's chain to `MC_TEST_LOG_DIR`
- `Mini CapsuleTests/Support/TestTags.swift` — `@Tag` declarations (`.unit`, `.integration`)
- `Mini CapsuleTests/Logging/LogFacadeTests.swift` — façade fan-out + ergonomic API
- `Mini CapsuleTests/Logging/OSLogSinkTests.swift` — `formatLine` formatting + privacy invariant
- `Mini CapsuleTests/Logging/FileSinkTests.swift` — JSONL round-trip + rotation
- `Mini CapsuleTests/MetaCoverageTests.swift` — reads the coverage manifest, enforces the gate

**New repo-root / infra files:**
- `MiniCapsule.xctestplan` — tiered test plan
- `Scripts/run-tests.sh` — runner + archival + gates
- `docs/testing/coverage-manifest.json` — machine-readable feature→coverage source of truth
- `docs/testing/traceability-matrix.md` — human-readable matrix (mirrors the manifest)
- `docs/testing/manual-checklist.md` — T4 manual checklist skeleton
- `.github/workflows/tests.yml` — CI (fast config)

**Modified:**
- `.gitignore` — add `TestResults/`

---

## Task 1: Log value types (`LogEvent`, `LogLevel`, `LogCategory`)

**Files:**
- Create: `Mini Capsule/Logging/LogEvent.swift`
- Test: `Mini CapsuleTests/Logging/LogFacadeTests.swift` (first test lives here; façade added Task 2)

**Interfaces:**
- Produces:
  - `enum LogCategory: String, Codable, Sendable, CaseIterable { case capture, dedup, store, paste, hotkey, settings, window, menubar, cleanup, ui, app }`
  - `enum LogLevel: Int, Codable, Sendable, Comparable { case debug, info, notice, warning, error, fault }`
  - `struct LogEvent: Codable, Sendable, Equatable` with `init(category:level:message:metadata:correlationID:timestamp:)` where `metadata` defaults to `[:]`, `correlationID` defaults to `nil`, `timestamp` defaults to `Date()`.

- [ ] **Step 1: Write the failing test**

Create `Mini CapsuleTests/Logging/LogFacadeTests.swift`:

```swift
import Testing
import Foundation
@testable import Mini_Capsule

@Suite struct LogEventTests {
    @Test func eventDefaultsAreEmpty() {
        let e = LogEvent(category: .capture, level: .info, message: "hi")
        #expect(e.metadata.isEmpty)
        #expect(e.correlationID == nil)
        #expect(e.category == .capture)
        #expect(e.level == .info)
        #expect(e.message == "hi")
    }

    @Test func levelIsComparable() {
        #expect(LogLevel.debug < LogLevel.error)
        #expect(LogLevel.fault > LogLevel.warning)
    }

    @Test func eventRoundTripsThroughCodable() throws {
        let e = LogEvent(category: .store, level: .error, message: "save failed",
                         metadata: ["id": "E7", "count": "3"], correlationID: "a1b2")
        let data = try JSONEncoder().encode(e)
        let decoded = try JSONDecoder().decode(LogEvent.self, from: data)
        #expect(decoded == e)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/LogEventTests" 2>&1 | tail -20`
Expected: FAIL — `cannot find 'LogEvent' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Mini Capsule/Logging/LogEvent.swift`:

```swift
import Foundation

/// One log subsystem. One os.Logger category maps to each case.
enum LogCategory: String, Codable, Sendable, CaseIterable {
    case capture, dedup, store, paste, hotkey, settings, window, menubar, cleanup, ui, app
}

enum LogLevel: Int, Codable, Sendable, Comparable {
    case debug, info, notice, warning, error, fault
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A single structured log record. `metadata` holds counts/types/ids ONLY —
/// never clipboard content. `correlationID` threads one capture/paste chain.
struct LogEvent: Codable, Sendable, Equatable {
    let timestamp: Date
    let category: LogCategory
    let level: LogLevel
    let message: String
    let metadata: [String: String]
    let correlationID: String?

    init(category: LogCategory,
         level: LogLevel,
         message: String,
         metadata: [String: String] = [:],
         correlationID: String? = nil,
         timestamp: Date = Date()) {
        self.timestamp = timestamp
        self.category = category
        self.level = level
        self.message = message
        self.metadata = metadata
        self.correlationID = correlationID
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/LogEventTests" 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add "Mini Capsule/Logging/LogEvent.swift" "Mini CapsuleTests/Logging/LogFacadeTests.swift"
git commit -m "feat(logging): add LogEvent/LogLevel/LogCategory value types"
```

---

## Task 2: `LogSink` protocol + `Log` façade + ergonomic API

**Files:**
- Create: `Mini Capsule/Logging/LogSink.swift`
- Create: `Mini CapsuleTests/Support/InMemoryLogSink.swift`
- Modify: `Mini CapsuleTests/Logging/LogFacadeTests.swift` (add façade tests)

**Interfaces:**
- Consumes: `LogEvent`, `LogCategory`, `LogLevel` (Task 1).
- Produces:
  - `protocol LogSink: Sendable { func write(_ event: LogEvent) }`
  - `extension LogSink { func log(_ category: LogCategory, _ level: LogLevel, _ message: String, metadata: [String: String] = [:], correlationID: String? = nil) }`
  - `final class Log: LogSink, @unchecked Sendable` with `init(sinks: [LogSink])` and `static let shared`.
  - Test support: `final class InMemoryLogSink: LogSink, @unchecked Sendable` exposing `var events: [LogEvent]`, `func events(in: LogCategory) -> [LogEvent]`, `func messages() -> [String]`.

- [ ] **Step 1: Write the failing test**

Append to `Mini CapsuleTests/Logging/LogFacadeTests.swift`:

```swift
@Suite struct LogFacadeTests {
    @Test func facadeFansOutToAllSinks() {
        let a = InMemoryLogSink()
        let b = InMemoryLogSink()
        let log = Log(sinks: [a, b])
        log.log(.capture, .info, "poll", metadata: ["cc": "42"], correlationID: "x1")
        #expect(a.events.count == 1)
        #expect(b.events.count == 1)
        #expect(a.events.first?.message == "poll")
        #expect(a.events.first?.metadata["cc"] == "42")
        #expect(a.events.first?.correlationID == "x1")
    }

    @Test func ergonomicLogBuildsEventWithDefaults() {
        let sink = InMemoryLogSink()
        sink.log(.store, .error, "boom")
        let e = sink.events.first
        #expect(e?.category == .store)
        #expect(e?.level == .error)
        #expect(e?.metadata.isEmpty == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/LogFacadeTests" 2>&1 | tail -20`
Expected: FAIL — `cannot find 'Log' in scope`, `cannot find 'InMemoryLogSink' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Mini Capsule/Logging/LogSink.swift`:

```swift
import Foundation

/// A destination for log events. Implementations must be thread-safe.
protocol LogSink: Sendable {
    func write(_ event: LogEvent)
}

extension LogSink {
    /// Ergonomic entry point: build a `LogEvent` and write it.
    func log(_ category: LogCategory,
             _ level: LogLevel,
             _ message: String,
             metadata: [String: String] = [:],
             correlationID: String? = nil) {
        write(LogEvent(category: category, level: level, message: message,
                       metadata: metadata, correlationID: correlationID))
    }
}

/// Fan-out façade. Production wires an OSLogSink + FileSink; tests inject an
/// InMemoryLogSink. Services depend on `LogSink` (default `Log.shared`).
final class Log: LogSink, @unchecked Sendable {
    static let shared = Log(sinks: [OSLogSink(), FileSink()])
    private let sinks: [LogSink]
    init(sinks: [LogSink]) { self.sinks = sinks }
    func write(_ event: LogEvent) {
        for sink in sinks { sink.write(event) }
    }
}
```

Create `Mini CapsuleTests/Support/InMemoryLogSink.swift`:

```swift
import Foundation
@testable import Mini_Capsule

/// Test sink that records events in order. Thread-safe.
final class InMemoryLogSink: LogSink, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [LogEvent] = []

    var events: [LogEvent] { lock.withLock { _events } }
    func write(_ event: LogEvent) { lock.withLock { _events.append(event) } }
    func events(in category: LogCategory) -> [LogEvent] { events.filter { $0.category == category } }
    func messages() -> [String] { events.map(\.message) }
    func reset() { lock.withLock { _events.removeAll() } }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/LogFacadeTests" 2>&1 | tail -20`
Expected: PASS (2 tests). Note: `Log.shared` references `OSLogSink`/`FileSink` which don't exist yet — but `Log.shared` is lazy and unused here, so compilation of `Log` requires those symbols. **Because `Log.shared`'s initializer names `OSLogSink()` and `FileSink()`, the file will not compile until Tasks 3–4 land.** To keep this task self-contained, temporarily define the two as empty stubs at the bottom of `LogSink.swift`:

```swift
// TEMP stubs — replaced by real files in Tasks 3 & 4.
struct OSLogSink: LogSink { func write(_ event: LogEvent) {} }
final class FileSink: LogSink, @unchecked Sendable { func write(_ event: LogEvent) {} }
```

Re-run; expected PASS. (Tasks 3 and 4 delete these stubs when creating the real files.)

- [ ] **Step 5: Commit**

```bash
git add "Mini Capsule/Logging/LogSink.swift" "Mini CapsuleTests/Support/InMemoryLogSink.swift" "Mini CapsuleTests/Logging/LogFacadeTests.swift"
git commit -m "feat(logging): add LogSink protocol, Log facade, InMemoryLogSink"
```

---

## Task 3: `OSLogSink` with a pure, testable formatter

**Files:**
- Create: `Mini Capsule/Logging/OSLogSink.swift`
- Modify: `Mini Capsule/Logging/LogSink.swift` (delete the temp `OSLogSink` stub)
- Create: `Mini CapsuleTests/Logging/OSLogSinkTests.swift`

**Interfaces:**
- Consumes: `LogEvent`, `LogSink` (Tasks 1–2).
- Produces: `struct OSLogSink: LogSink` with `static func formatLine(_ event: LogEvent) -> String`.

- [ ] **Step 1: Write the failing test**

Create `Mini CapsuleTests/Logging/OSLogSinkTests.swift`:

```swift
import Testing
import Foundation
@testable import Mini_Capsule

@Suite struct OSLogSinkTests {
    @Test func formatLineIncludesCorrelationMessageAndSortedMetadata() {
        let e = LogEvent(category: .capture, level: .info, message: "readPasteboard",
                         metadata: ["type": "image", "bytes": "48213"], correlationID: "a1b2")
        let line = OSLogSink.formatLine(e)
        #expect(line == "[a1b2] readPasteboard bytes=48213 type=image")
    }

    @Test func formatLineWithoutCorrelationOmitsBracket() {
        let e = LogEvent(category: .app, level: .notice, message: "launch")
        #expect(OSLogSink.formatLine(e) == "launch")
    }

    @Test func writeDoesNotCrash() {
        // Smoke test: os.Logger output isn't assertable here; just ensure no trap.
        OSLogSink().write(LogEvent(category: .app, level: .debug, message: "x"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

First delete the temp stub in `LogSink.swift` (the line `struct OSLogSink: LogSink { func write(_ event: LogEvent) {} }`).
Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/OSLogSinkTests" 2>&1 | tail -20`
Expected: FAIL — `type 'OSLogSink' has no member 'formatLine'` (or compile error from the removed stub).

- [ ] **Step 3: Write minimal implementation**

Create `Mini Capsule/Logging/OSLogSink.swift`:

```swift
import Foundation
import os

/// Routes events to Apple's unified logging. Each LogCategory becomes an
/// os.Logger category under one subsystem, visible in Console.app / `log stream`.
struct OSLogSink: LogSink {
    static let subsystem = "com.minicapsule.app"

    /// Pure formatter (unit-testable). Metadata is rendered as sorted `k=v` pairs
    /// so output is deterministic. Content never reaches here by construction.
    static func formatLine(_ event: LogEvent) -> String {
        let meta = event.metadata
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: " ")
        let cid = event.correlationID.map { "[\($0)] " } ?? ""
        let base = "\(cid)\(event.message)"
        return meta.isEmpty ? base : "\(base) \(meta)"
    }

    func write(_ event: LogEvent) {
        let logger = Logger(subsystem: Self.subsystem, category: event.category.rawValue)
        let line = Self.formatLine(event)
        // `.private` is a second guard; by policy `line` already excludes content.
        switch event.level {
        case .debug:   logger.debug("\(line, privacy: .private)")
        case .info:    logger.info("\(line, privacy: .private)")
        case .notice:  logger.notice("\(line, privacy: .private)")
        case .warning: logger.warning("\(line, privacy: .private)")
        case .error:   logger.error("\(line, privacy: .private)")
        case .fault:   logger.fault("\(line, privacy: .private)")
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/OSLogSinkTests" 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add "Mini Capsule/Logging/OSLogSink.swift" "Mini Capsule/Logging/LogSink.swift" "Mini CapsuleTests/Logging/OSLogSinkTests.swift"
git commit -m "feat(logging): add OSLogSink with pure testable formatter"
```

---

## Task 4: `FileSink` — JSONL append with size rotation

**Files:**
- Create: `Mini Capsule/Logging/FileSink.swift`
- Modify: `Mini Capsule/Logging/LogSink.swift` (delete the temp `FileSink` stub)
- Create: `Mini CapsuleTests/Logging/FileSinkTests.swift`

**Interfaces:**
- Consumes: `LogEvent`, `LogSink`.
- Produces: `final class FileSink: LogSink, @unchecked Sendable` with `init(directory: URL? = nil, fileName: String = "session.jsonl", maxBytes: Int = 5_000_000)`, `var fileURL: URL`, and `static func defaultDirectory() -> URL`.

- [ ] **Step 1: Write the failing test**

Create `Mini CapsuleTests/Logging/FileSinkTests.swift`:

```swift
import Testing
import Foundation
@testable import Mini_Capsule

@Suite struct FileSinkTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("filesink-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func writesOneJSONLinePerEvent() throws {
        let dir = tempDir()
        let sink = FileSink(directory: dir, fileName: "t.jsonl")
        sink.write(LogEvent(category: .capture, level: .info, message: "a"))
        sink.write(LogEvent(category: .store, level: .error, message: "b"))

        let text = try String(contentsOf: sink.fileURL, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 2)
        let first = try JSONDecoder().decode(LogEvent.self, from: Data(lines[0].utf8))
        #expect(first.message == "a")
    }

    @Test func rotatesWhenOverMaxBytes() throws {
        let dir = tempDir()
        let sink = FileSink(directory: dir, fileName: "t.jsonl", maxBytes: 200)
        for i in 0..<50 { sink.write(LogEvent(category: .app, level: .info, message: "line-\(i)")) }
        let rotated = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("t-") && $0.hasSuffix(".jsonl") }
        #expect(!rotated.isEmpty, "expected at least one rotated file")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Delete the temp `FileSink` stub in `LogSink.swift`.
Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/FileSinkTests" 2>&1 | tail -20`
Expected: FAIL — `argument passed to call that takes no arguments` / missing initializer.

- [ ] **Step 3: Write minimal implementation**

Create `Mini Capsule/Logging/FileSink.swift`:

```swift
import Foundation

/// Appends events as JSON Lines to a rotating file. Thread-safe via a serial queue.
final class FileSink: LogSink, @unchecked Sendable {
    private let directory: URL
    private let fileName: String
    private let maxBytes: Int
    private let queue = DispatchQueue(label: "com.minicapsule.filesink")
    private let encoder: JSONEncoder

    init(directory: URL? = nil, fileName: String = "session.jsonl", maxBytes: Int = 5_000_000) {
        self.directory = directory ?? FileSink.defaultDirectory()
        self.fileName = fileName
        self.maxBytes = maxBytes
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Mini Capsule/logs", isDirectory: true)
    }

    var fileURL: URL { directory.appendingPathComponent(fileName) }

    func write(_ event: LogEvent) {
        queue.sync {
            rotateIfNeeded()
            guard var data = try? encoder.encode(event) else { return }
            data.append(0x0A) // '\n'
            if FileManager.default.fileExists(atPath: fileURL.path),
               let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int, size > maxBytes else { return }
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let base = (fileName as NSString).deletingPathExtension
        let rotated = directory.appendingPathComponent("\(base)-\(stamp).jsonl")
        try? FileManager.default.moveItem(at: fileURL, to: rotated)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/FileSinkTests" 2>&1 | tail -20`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add "Mini Capsule/Logging/FileSink.swift" "Mini Capsule/Logging/LogSink.swift" "Mini CapsuleTests/Logging/FileSinkTests.swift"
git commit -m "feat(logging): add FileSink JSONL archive with size rotation"
```

---

## Task 5: Test-support — `@Tag`s + `LogArchive` per-test chain writer

**Files:**
- Create: `Mini CapsuleTests/Support/TestTags.swift`
- Create: `Mini CapsuleTests/Support/LogArchive.swift`
- Create: `Mini CapsuleTests/Support/LogArchiveTests.swift`

**Interfaces:**
- Consumes: `LogEvent`, `InMemoryLogSink`.
- Produces:
  - `extension Tag { @Tag static var unit: Self; @Tag static var integration: Self }`
  - `enum LogArchive { static func write(_ events: [LogEvent], testID: String) }` — writes `<MC_TEST_LOG_DIR>/logs/<testID>.jsonl` when `MC_TEST_LOG_DIR` is set; no-op otherwise. `testID` is sanitized (non-alphanumerics → `_`).

- [ ] **Step 1: Write the failing test**

Create `Mini CapsuleTests/Support/LogArchiveTests.swift`:

```swift
import Testing
import Foundation
@testable import Mini_Capsule

@Suite struct LogArchiveTests {
    @Test func writesChainToConfiguredDir() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-\(UUID().uuidString)", isDirectory: true)
        setenv("MC_TEST_LOG_DIR", dir.path, 1)
        defer { unsetenv("MC_TEST_LOG_DIR") }

        let events = [
            LogEvent(category: .capture, level: .info, message: "poll", correlationID: "c1"),
            LogEvent(category: .store, level: .info, message: "insert", correlationID: "c1"),
        ]
        LogArchive.write(events, testID: "Suite/case name!")

        let file = dir.appendingPathComponent("logs/Suite_case_name_.jsonl")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.split(separator: "\n").count == 2)
    }

    @Test func noopWhenEnvUnset() {
        unsetenv("MC_TEST_LOG_DIR")
        // Must not crash and must not create anything.
        LogArchive.write([LogEvent(category: .app, level: .info, message: "x")], testID: "t")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/LogArchiveTests" 2>&1 | tail -20`
Expected: FAIL — `cannot find 'LogArchive' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Mini CapsuleTests/Support/TestTags.swift`:

```swift
import Testing

extension Tag {
    @Tag static var unit: Self
    @Tag static var integration: Self
}
```

Create `Mini CapsuleTests/Support/LogArchive.swift`:

```swift
import Foundation
@testable import Mini_Capsule

/// Always-capture archival: writes a test's full log chain to
/// `$MC_TEST_LOG_DIR/logs/<testID>.jsonl`. The runner promotes failing tests'
/// files into `failures/`. No-op when the env var is unset (e.g. Xcode runs).
enum LogArchive {
    static func write(_ events: [LogEvent], testID: String) {
        guard let root = ProcessInfo.processInfo.environment["MC_TEST_LOG_DIR"], !root.isEmpty else { return }
        let logsDir = URL(fileURLWithPath: root).appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let safe = testID.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        let file = logsDir.appendingPathComponent("\(String(safe)).jsonl")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var blob = Data()
        for e in events {
            guard let d = try? encoder.encode(e) else { continue }
            blob.append(d); blob.append(0x0A)
        }
        try? blob.write(to: file)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/LogArchiveTests" 2>&1 | tail -20`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add "Mini CapsuleTests/Support/TestTags.swift" "Mini CapsuleTests/Support/LogArchive.swift" "Mini CapsuleTests/Support/LogArchiveTests.swift"
git commit -m "test(support): add @Tag declarations and LogArchive chain writer"
```

---

## Task 6: Coverage manifest + `MetaCoverageTests` gate

**Files:**
- Create: `docs/testing/coverage-manifest.json`
- Create: `docs/testing/traceability-matrix.md`
- Create: `Mini CapsuleTests/MetaCoverageTests.swift`

**Interfaces:**
- Consumes: nothing from prior tasks (reads a repo file via `#filePath`).
- Produces: the manifest schema `{ "features": [ { "id": Int, "name": String, "tier": [String], "tests": [String], "checklist": [String], "status": "covered" | "pending", "plan": String? } ] }` and a test suite `MetaCoverageTests` enforcing the invariant.

**Invariant enforced now:** every feature is `covered` (with ≥1 test or checklist link) **or** `pending` (with a `plan` reference). Plan 4 flips the final switch (`requireAllCovered`) so no `pending` may remain.

- [ ] **Step 1: Write the failing test**

Create `Mini CapsuleTests/MetaCoverageTests.swift`:

```swift
import Testing
import Foundation

@Suite struct MetaCoverageTests {
    /// Toggle flipped to `true` in Plan 4 once every feature is covered.
    static let requireAllCovered = false

    struct Feature: Decodable {
        let id: Int
        let name: String
        let tier: [String]
        let tests: [String]
        let checklist: [String]
        let status: String
        let plan: String?
    }
    struct Manifest: Decodable { let features: [Feature] }

    static func manifestURL(file: StaticString = #filePath) -> URL {
        // <repo>/Mini CapsuleTests/MetaCoverageTests.swift → walk up to repo root.
        var url = URL(fileURLWithPath: "\(file)")
        url.deleteLastPathComponent() // Mini CapsuleTests/
        url.deleteLastPathComponent() // repo root
        return url.appendingPathComponent("docs/testing/coverage-manifest.json")
    }

    static func load() throws -> Manifest {
        let data = try Data(contentsOf: manifestURL())
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    @Test func everyFeatureIsCoveredOrExplicitlyPending() throws {
        let m = try Self.load()
        #expect(!m.features.isEmpty)
        for f in m.features {
            switch f.status {
            case "covered":
                #expect(f.tests.count + f.checklist.count >= 1,
                        "Feature #\(f.id) '\(f.name)' is covered but links no test/checklist")
            case "pending":
                #expect(f.plan != nil && !(f.plan ?? "").isEmpty,
                        "Feature #\(f.id) '\(f.name)' is pending but names no plan")
            default:
                Issue.record("Feature #\(f.id) '\(f.name)' has invalid status '\(f.status)'")
            }
        }
    }

    @Test func noFeatureRemainsPending() throws {
        try #require(Self.requireAllCovered == false || {
            let m = try Self.load()
            return m.features.allSatisfy { $0.status == "covered" }
        }())
    }

    @Test func featureIDsAreUniqueAndComplete() throws {
        let m = try Self.load()
        let ids = Set(m.features.map(\.id))
        #expect(ids.count == m.features.count, "duplicate feature ids")
        #expect(ids == Set(1...18), "manifest must enumerate features 1...18 from the spec inventory")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/MetaCoverageTests" 2>&1 | tail -20`
Expected: FAIL — manifest file not found (thrown error).

- [ ] **Step 3: Write minimal implementation**

Create `docs/testing/coverage-manifest.json` (18 features from the spec §4 inventory; rows already covered today are `covered`, the rest `pending` with their plan):

```json
{
  "features": [
    { "id": 1,  "name": "ClipboardMonitor — capture",      "tier": ["T2"],       "tests": [], "checklist": [], "status": "pending", "plan": "2026-07-12-seams-integration-plan" },
    { "id": 2,  "name": "ClipboardMonitor — readPasteboard","tier": ["T1"],       "tests": [], "checklist": [], "status": "pending", "plan": "2026-07-12-backfill-capture-paste-plan" },
    { "id": 3,  "name": "ClipboardMonitor — dedup/cap",     "tier": ["T1","T2"],  "tests": ["ClipboardMonitorTests"], "checklist": [], "status": "pending", "plan": "2026-07-12-backfill-capture-paste-plan" },
    { "id": 4,  "name": "PasteService — suppression",       "tier": ["T1"],       "tests": ["PasteServiceTests"], "checklist": [], "status": "pending", "plan": "2026-07-12-backfill-capture-paste-plan" },
    { "id": 5,  "name": "PasteService — copy/paste",        "tier": ["T1","T2"],  "tests": ["PasteServiceTests"], "checklist": ["M1","M2","M7"], "status": "pending", "plan": "2026-07-12-backfill-capture-paste-plan" },
    { "id": 6,  "name": "HotKeyParser",                     "tier": ["T1"],       "tests": ["HotKeyParserTests"], "checklist": [], "status": "covered" },
    { "id": 7,  "name": "HotKeyCenter",                     "tier": ["T2"],       "tests": [], "checklist": ["M3","M4"], "status": "pending", "plan": "2026-07-12-seams-integration-plan" },
    { "id": 8,  "name": "Settings (Data/Store/Persistence)","tier": ["T1","T2"],  "tests": ["SettingsDataTests","SettingsPersistenceTests"], "checklist": [], "status": "pending", "plan": "2026-07-12-backfill-settings-viewmodels-plan" },
    { "id": 9,  "name": "ClipboardListViewModel",           "tier": ["T1"],       "tests": ["ClipboardListViewModelTests"], "checklist": [], "status": "pending", "plan": "2026-07-12-backfill-settings-viewmodels-plan" },
    { "id": 10, "name": "CapsuleViewModel",                 "tier": ["T1"],       "tests": ["CapsuleViewModelTests"], "checklist": [], "status": "pending", "plan": "2026-07-12-backfill-settings-viewmodels-plan" },
    { "id": 11, "name": "MenuBarService",                   "tier": ["T2","T3"],  "tests": ["MenuBarServiceTests"], "checklist": ["M9"], "status": "pending", "plan": "2026-07-12-backfill-settings-viewmodels-plan" },
    { "id": 12, "name": "FrequencyCleanupService",          "tier": ["T1"],       "tests": ["FrequencyCleanupServiceTests"], "checklist": [], "status": "pending", "plan": "2026-07-12-backfill-settings-viewmodels-plan" },
    { "id": 13, "name": "CapsuleWindowController",          "tier": ["T3","T4"],  "tests": [], "checklist": ["M5","M6"], "status": "pending", "plan": "2026-07-12-backfill-settings-viewmodels-plan" },
    { "id": 14, "name": "ColorHex",                         "tier": ["T1"],       "tests": ["ColorHexTests"], "checklist": [], "status": "covered" },
    { "id": 15, "name": "App wiring / AppDelegate",         "tier": ["T3","T4"],  "tests": [], "checklist": ["M8"], "status": "pending", "plan": "2026-07-12-backfill-settings-viewmodels-plan" },
    { "id": 16, "name": "Models (ClipItem/Item)",           "tier": ["T1"],       "tests": ["Mini_CapsuleTests"], "checklist": [], "status": "pending", "plan": "2026-07-12-backfill-settings-viewmodels-plan" },
    { "id": 17, "name": "UI views x9",                      "tier": ["T3","T4"],  "tests": [], "checklist": ["M5","M6","M9"], "status": "pending", "plan": "2026-07-12-backfill-settings-viewmodels-plan" },
    { "id": 18, "name": "Logging facade",                   "tier": ["T1"],       "tests": ["LogEventTests","LogFacadeTests","OSLogSinkTests","FileSinkTests","LogArchiveTests"], "checklist": [], "status": "covered" }
  ]
}
```

Create `docs/testing/traceability-matrix.md`:

```markdown
# Traceability Matrix

The machine-readable source of truth is `coverage-manifest.json`; `MetaCoverageTests`
enforces it. This table mirrors it for humans. `status: pending` rows are backfilled by
the named plan; Plan 4 flips `MetaCoverageTests.requireAllCovered` so no row may stay pending.

| # | Feature | Tier | Tests | Checklist | Status |
|---|---------|------|-------|-----------|--------|
| 1 | ClipboardMonitor — capture | T2 | — | — | pending (seams-integration) |
| 2 | ClipboardMonitor — readPasteboard | T1 | — | — | pending (backfill-capture-paste) |
| 3 | ClipboardMonitor — dedup/cap | T1,T2 | ClipboardMonitorTests | — | pending (backfill-capture-paste) |
| 4 | PasteService — suppression | T1 | PasteServiceTests | — | pending (backfill-capture-paste) |
| 5 | PasteService — copy/paste | T1,T2 | PasteServiceTests | M1,M2,M7 | pending (backfill-capture-paste) |
| 6 | HotKeyParser | T1 | HotKeyParserTests | — | covered |
| 7 | HotKeyCenter | T2 | — | M3,M4 | pending (seams-integration) |
| 8 | Settings | T1,T2 | SettingsDataTests, SettingsPersistenceTests | — | pending (backfill-settings-viewmodels) |
| 9 | ClipboardListViewModel | T1 | ClipboardListViewModelTests | — | pending (backfill-settings-viewmodels) |
| 10 | CapsuleViewModel | T1 | CapsuleViewModelTests | — | pending (backfill-settings-viewmodels) |
| 11 | MenuBarService | T2,T3 | MenuBarServiceTests | M9 | pending (backfill-settings-viewmodels) |
| 12 | FrequencyCleanupService | T1 | FrequencyCleanupServiceTests | — | pending (backfill-settings-viewmodels) |
| 13 | CapsuleWindowController | T3,T4 | — | M5,M6 | pending (backfill-settings-viewmodels) |
| 14 | ColorHex | T1 | ColorHexTests | — | covered |
| 15 | App wiring / AppDelegate | T3,T4 | — | M8 | pending (backfill-settings-viewmodels) |
| 16 | Models | T1 | Mini_CapsuleTests | — | pending (backfill-settings-viewmodels) |
| 17 | UI views ×9 | T3,T4 | — | M5,M6,M9 | pending (backfill-settings-viewmodels) |
| 18 | Logging facade | T1 | LogEventTests, LogFacadeTests, OSLogSinkTests, FileSinkTests, LogArchiveTests | — | covered |
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/MetaCoverageTests" 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add docs/testing/coverage-manifest.json docs/testing/traceability-matrix.md "Mini CapsuleTests/MetaCoverageTests.swift"
git commit -m "test(meta): add coverage manifest + traceability matrix + gate"
```

---

## Task 7: Tiered test plan + `.gitignore`

**Files:**
- Create: `MiniCapsule.xctestplan`
- Modify: `.gitignore`

**Interfaces:** none (configuration only).

**Note on tier filtering:** the two Swift Testing tags `.unit`/`.integration` are applied to suites in later plans. This test plan defines coverage + env; the `fast`/`full` split is by *target selection* (UI target excluded from `fast`). The runner (Task 8) selects a config by name.

- [ ] **Step 1: Create the test plan**

Create `MiniCapsule.xctestplan`:

```json
{
  "configurations" : [
    {
      "id" : "FAST-0000-0000-0000-000000000001",
      "name" : "fast",
      "options" : {
        "environmentVariableEntries" : [
          { "key" : "MC_TEST_LOG_DIR", "value" : "$(SRCROOT)/TestResults/current" }
        ]
      }
    },
    {
      "id" : "FULL-0000-0000-0000-000000000002",
      "name" : "full",
      "options" : {
        "environmentVariableEntries" : [
          { "key" : "MC_TEST_LOG_DIR", "value" : "$(SRCROOT)/TestResults/current" }
        ]
      }
    }
  ],
  "defaultOptions" : {
    "codeCoverage" : {
      "targets" : [
        { "containerPath" : "container:Mini Capsule.xcodeproj", "identifier" : "Mini Capsule", "name" : "Mini Capsule" }
      ]
    }
  },
  "testTargets" : [
    {
      "target" : { "containerPath" : "container:Mini Capsule.xcodeproj", "identifier" : "Mini CapsuleTests", "name" : "Mini CapsuleTests" }
    },
    {
      "enabled" : false,
      "selectedConfigurations" : [ "FULL-0000-0000-0000-000000000002" ],
      "target" : { "containerPath" : "container:Mini Capsule.xcodeproj", "identifier" : "Mini CapsuleUITests", "name" : "Mini CapsuleUITests" }
    }
  ],
  "version" : 1
}
```

> **Verify identifiers:** the `identifier`/`name` for each target must match the project. Confirm with:
> `xcodebuild -project "Mini Capsule.xcodeproj" -list`
> If the UI test target has a different name, update the `Mini CapsuleUITests` entry. If Xcode rewrites this file when first opened, accept its normalized version.

- [ ] **Step 2: Update `.gitignore`**

Add these lines to `.gitignore` (append; do not remove existing entries):

```gitignore
# Automated-test outputs
TestResults/
```

- [ ] **Step 3: Verify the plan is usable**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -testPlan MiniCapsule -only-testing:"Mini CapsuleTests/MetaCoverageTests" 2>&1 | tail -20`
Expected: PASS — confirms the scheme accepts `-testPlan MiniCapsule`.

> If `xcodebuild` reports the scheme has no test plans, open the project in Xcode once (Product → Test Plan → Add Existing Plan → select `MiniCapsule.xctestplan`) so the scheme references it, then re-run. Commit the resulting scheme change together with this task.

- [ ] **Step 4: Commit**

```bash
git add MiniCapsule.xctestplan .gitignore "Mini Capsule.xcodeproj/xcshareddata/xcschemes/Mini Capsule.xcscheme"
git commit -m "test(plan): add tiered MiniCapsule.xctestplan and ignore TestResults"
```

---

## Task 8: `run-tests.sh` — run, archive, promote failures, gate

**Files:**
- Create: `Scripts/run-tests.sh` (executable)

**Interfaces:**
- Consumes: `MiniCapsule.xctestplan`, `MC_TEST_LOG_DIR` convention, `coverage-manifest.json`.
- Produces: a `TestResults/<timestamp>/` directory with `result.xcresult`, `logs/`, `failures/`, `coverage.json`, `summary.md`; exit code ≠0 on failure / coverage-below-gate.

- [ ] **Step 1: Write the script**

Create `Scripts/run-tests.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: Scripts/run-tests.sh [fast|full]   (default: fast)
CONFIG="${1:-fast}"
PROJECT="Mini Capsule.xcodeproj"
SCHEME="Mini Capsule"
PLAN="MiniCapsule"
COVERAGE_GATE="${COVERAGE_GATE:-85}"   # percent, applied to logic files
LOGIC_PREFIXES=("Mini Capsule/Services/" "Mini Capsule/Settings/" "Mini Capsule/Utilities/" "Mini Capsule/Logging/")

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

XCODEBUILD="xcodebuild"
command -v "$XCODEBUILD" >/dev/null 2>&1 || XCODEBUILD="/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"

TS="$(date +%Y-%m-%d-%H%M%S)"
OUT="TestResults/$TS"
mkdir -p "$OUT/logs" "$OUT/failures"
# The xctestplan writes per-test chains here (MC_TEST_LOG_DIR points at TestResults/current).
rm -rf "TestResults/current"; mkdir -p "TestResults/current/logs"

echo "▶ Running test plan '$PLAN' config '$CONFIG'…"
set +e
"$XCODEBUILD" test \
  -project "$PROJECT" -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -testPlan "$PLAN" \
  -resultBundlePath "$OUT/result.xcresult" \
  -enableCodeCoverage YES \
  MC_TEST_LOG_DIR="$ROOT/TestResults/current" \
  2>&1 | tee "$OUT/xcodebuild.log"
TEST_STATUS=${PIPESTATUS[0]}
set -e

# Move the always-captured per-test chains into this run.
if [ -d "TestResults/current/logs" ]; then
  cp -R "TestResults/current/logs/." "$OUT/logs/" 2>/dev/null || true
fi

# --- Extract failures from the .xcresult and promote their chains ---
FAILED_TESTS=()
if [ -d "$OUT/result.xcresult" ]; then
  # xcresulttool JSON shape varies by Xcode; grep test identifiers that failed.
  xcrun xcresulttool get test-results tests --path "$OUT/result.xcresult" --format json > "$OUT/tests.json" 2>/dev/null \
    || xcrun xcresulttool get --format json --path "$OUT/result.xcresult" > "$OUT/tests.json" 2>/dev/null || true
  # Collect names of failing tests (best-effort across Xcode versions).
  while IFS= read -r name; do
    [ -n "$name" ] && FAILED_TESTS+=("$name")
  done < <(grep -oE '"(name|identifier)"[ ]*:[ ]*"[^"]+"' "$OUT/tests.json" 2>/dev/null \
            | sed -E 's/.*: *"([^"]+)".*/\1/' | sort -u | grep -iE 'test' || true)
fi

# Promote: for each failing test, copy its archived chain into failures/.
promoted=0
for f in "${FAILED_TESTS[@]:-}"; do
  safe="$(echo "$f" | sed -E 's/[^A-Za-z0-9]/_/g')"
  if [ -f "$OUT/logs/$safe.jsonl" ]; then
    cp "$OUT/logs/$safe.jsonl" "$OUT/failures/$safe.log"
    promoted=$((promoted+1))
  fi
done

# --- Coverage (scoped to logic files) ---
COV_PCT="n/a"
if [ -d "$OUT/result.xcresult" ]; then
  xcrun xccov view --report --json "$OUT/result.xcresult" > "$OUT/coverage.json" 2>/dev/null || echo '{}' > "$OUT/coverage.json"
  COV_PCT=$(python3 - "$OUT/coverage.json" "${LOGIC_PREFIXES[@]}" <<'PY'
import json, sys
report_path = sys.argv[1]; prefixes = tuple(sys.argv[2:])
try:
    data = json.load(open(report_path))
except Exception:
    print("n/a"); sys.exit(0)
covered = executable = 0
for target in data.get("targets", []):
    for f in target.get("files", []):
        path = f.get("path", "")
        if any(p in path for p in prefixes):
            executable += f.get("executableLines", 0)
            covered += f.get("coveredLines", 0)
print(f"{(100.0*covered/executable):.1f}" if executable else "n/a")
PY
)
fi

# --- Summary ---
{
  echo "# Test run $TS  (config: $CONFIG)"
  echo ""
  echo "- xcodebuild exit: $TEST_STATUS"
  echo "- logic-file coverage: ${COV_PCT}% (gate ${COVERAGE_GATE}%)"
  echo "- failing tests: ${#FAILED_TESTS[@]:-0} (promoted chains: $promoted)"
  echo ""
  if [ "${#FAILED_TESTS[@]:-0}" -gt 0 ]; then
    echo "## Failures (open failures/<name>.log for the full chain)"
    for f in "${FAILED_TESTS[@]:-}"; do echo "- $f"; done
  fi
} > "$OUT/summary.md"
cat "$OUT/summary.md"

# --- Gates ---
GATE_FAIL=0
if [ "$TEST_STATUS" -ne 0 ]; then echo "✗ tests failed"; GATE_FAIL=1; fi
if [ "$COV_PCT" != "n/a" ]; then
  awk "BEGIN{exit !($COV_PCT < $COVERAGE_GATE)}" && { echo "✗ coverage $COV_PCT% < $COVERAGE_GATE%"; GATE_FAIL=1; }
fi
echo "Results: $OUT"
exit $GATE_FAIL
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x Scripts/run-tests.sh`

- [ ] **Step 3: Run it end-to-end**

Run: `Scripts/run-tests.sh fast 2>&1 | tail -30`
Expected: the pre-existing 104 tests + the new logging/meta tests PASS; prints a `summary.md`; creates `TestResults/<ts>/` with `logs/` populated; exit 0. (Coverage may print `n/a` until enough logic files are measured — that does not fail the gate.)

> **Xcode-version caveat:** `xcresulttool` subcommands changed across Xcode 15→16. If failure extraction prints nothing, adjust the two `xcrun xcresulttool` invocations to your installed version (`xcrun xcresulttool version`). The always-captured `logs/` are unaffected — only the automatic *promotion* of failures depends on this parsing.

- [ ] **Step 4: Commit**

```bash
git add Scripts/run-tests.sh
git commit -m "test(runner): add run-tests.sh with log archival, failure promotion, coverage gate"
```

---

## Task 9: CI workflow + manual-checklist skeleton

**Files:**
- Create: `.github/workflows/tests.yml`
- Create: `docs/testing/manual-checklist.md`

**Interfaces:** none (docs + CI config).

- [ ] **Step 1: Create the manual checklist**

Create `docs/testing/manual-checklist.md`:

```markdown
# T4 Manual Verification Checklist

Run before each release on a real machine with Accessibility + (optionally) Automation
permissions granted. Each item closes the inventory row(s) noted. Record pass/fail + date.

| ID | Steps | Expected | Covers |
|----|-------|----------|--------|
| M1 | Copy text in app A → open Mini Capsule → click the text item's paste action while a TextEdit doc is focused | Text is pasted into TextEdit at the caret | #5 |
| M2 | Copy an image (e.g. screenshot) → paste the image item into Preview/Notes | Image appears in the target app | #5 |
| M3 | With another app focused, press the show/hide global hotkey | Capsule shows/hides regardless of focused app | #7 |
| M4 | With another app focused, press the quick-paste global hotkey | Front history item is pasted into the focused app | #7 |
| M5 | Open several app windows; observe the capsule | Capsule floats above all windows and appears on all Spaces | #13, #17 |
| M6 | Drag the capsule to a new location; quit and relaunch | Capsule reappears at the dragged location | #13 |
| M7 | Revoke Accessibility permission for Mini Capsule; trigger a paste | Paste no-ops gracefully; a `.error` event is logged (check Console.app, subsystem com.minicapsule.app) | #5 |
| M8 | Toggle "Launch at login" in settings; reboot | App launches (or not) per the setting | #15 |
| M9 | Click the menu-bar icon → pick a recent item | Item is copied/pasted per its action | #11, #17 |

**How to read logs during manual testing:** `log stream --predicate 'subsystem == "com.minicapsule.app"' --info`
or open Console.app and filter by subsystem. Never expect clipboard *content* in logs — only metadata.
```

- [ ] **Step 2: Create the CI workflow**

Create `.github/workflows/tests.yml`:

```yaml
name: Tests
on:
  push:
    branches: [ main ]
  pull_request:

jobs:
  fast:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode.app
      - name: Run fast test plan
        run: Scripts/run-tests.sh fast
      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: TestResults/
```

> **Runner note:** the UI target is disabled in the `fast` config, so CI runs T1+T2 only. If the macOS runner image lacks the required Xcode, pin it via `xcode-select` to an installed version (`ls /Applications | grep Xcode`).

- [ ] **Step 3: Validate the workflow file locally**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/tests.yml')); print('yaml ok')"`
Expected: `yaml ok`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/tests.yml docs/testing/manual-checklist.md
git commit -m "ci: add fast test workflow + T4 manual checklist skeleton"
```

---

## Task 10: Full-suite green verification

**Files:** none (verification only).

- [ ] **Step 1: Run the complete existing + new suite via the plan**

Run: `Scripts/run-tests.sh fast 2>&1 | tee /tmp/mc-fast.log | tail -40`
Expected: exit 0. Confirm in the output:
- Pre-existing suites still pass (e.g. `ClipboardMonitorTests`, `PasteServiceTests`, `ColorHexTests`).
- New suites pass: `LogEventTests`, `LogFacadeTests`, `OSLogSinkTests`, `FileSinkTests`, `LogArchiveTests`, `MetaCoverageTests`.

- [ ] **Step 2: Confirm archival worked**

Run: `ls TestResults/*/logs/*.jsonl | head` and `cat TestResults/*/summary.md | tail -20`
Expected: at least one `.jsonl` chain file exists; `summary.md` reports 0 failures.

- [ ] **Step 3: Confirm the meta-gate is wired**

Run: `xcodebuild test -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' -only-testing:"Mini CapsuleTests/MetaCoverageTests/featureIDsAreUniqueAndComplete" 2>&1 | tail -10`
Expected: PASS — manifest enumerates features 1…18.

- [ ] **Step 4: Final commit (no-op if clean)**

```bash
git add -A && git commit -m "test: verify foundation suite green" --allow-empty
```

---

## Self-Review Notes (author)

- **Spec §5 (logging facade)** → Tasks 1–4. **§6 (per-failure report)** → Task 5 (always-capture) + Task 8 (promotion). **§8 (xctestplan)** → Task 7. **§9 (matrix + meta-check)** → Task 6. **§10 (runner + coverage gate)** → Task 8. **§11 (CI)** → Task 9. **§12 (manual checklist)** → Task 9.
- **Deferred to later plans (by design, tracked as `pending` in the manifest):** §7 seams + `SelfPasteTracker` + `checkPasteboard()` decomposition (Plan 2); readPasteboard/dedup/paste backfill (Plan 3); settings/viewmodels/menubar/cleanup backfill + flipping `requireAllCovered` (Plan 4).
- **Privacy rule** is enforced structurally (metadata-only API) and reinforced by `OSLogSink` `.private` annotations; a dedicated "no content in metadata" lint test is added in Plan 3 when real services start logging.
```

Follow-on plans (2–4) are named in the manifest so the meta-gate stays green until they land.
