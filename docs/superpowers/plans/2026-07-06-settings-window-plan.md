# Settings Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a system settings window (macOS Settings scene) with three tabs — Clipboard, Shortcuts, Advanced — backed by @AppStorage/UserDefaults.

**Architecture:** Central `SettingsStore` (ObservableObject) wraps `@AppStorage` keys. `Settings` scene in `Mini_CapsuleApp.swift` hosts a `TabView` with three settings views. The gear button in `CapsuleExpandedView` triggers `openSettings`. `ClipboardMonitor` and `FrequencyCleanupService` read values from `UserDefaults.standard`. Keyboard shortcuts stored as strings, registered via `NSEvent.addLocalMonitorForEvents`.

**Tech Stack:** SwiftUI, SwiftData, AppKit (NSEvent, NSSavePanel, NSOpenPanel), UserDefaults/@AppStorage

## Global Constraints

- Deployment target: macOS 26.5
- Use `Settings { }` scene (macOS 14+)
- Use `@AppStorage` for all persisted settings
- Chinese (Simplified) labels for all UI text
- Follow existing project patterns: `// Mini Capsule/Path/File.swift` header comments
- Existing `ClipboardMonitor` and `FrequencyCleanupService` must read settings from UserDefaults, not be passed as parameters

---

### Task 1: Create SettingsStore

**Files:**
- Create: `Mini Capsule/Settings/SettingsStore.swift`

**Interfaces:**
- Produces: `SettingsStore` class — `@MainActor ObservableObject` with `@AppStorage` properties (`historyMaxCount: Int`, `imageMaxSizeMB: Int`, `pollingInterval: Double`, `cleanupOnStartup: Bool`, `dedupEnabled: Bool`, `showHideShortcut: String`, `quickPasteShortcut: String`, `togglePinShortcut: String`, `iCloudSyncEnabled: Bool`); methods `resetAll()`, `exportData(context:) -> Data`, `importData(_:context:)`, `clearAllHistory(context:)`; static notification name `pollingIntervalDidChange`

- [ ] **Step 1: Create the SettingsStore.swift file**

```swift
// Mini Capsule/Settings/SettingsStore.swift
import SwiftUI
import SwiftData
import Foundation

extension Notification.Name {
    static let pollingIntervalDidChange = Notification.Name("SettingsPollingIntervalDidChange")
}

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
final class SettingsStore: ObservableObject {
    // MARK: - Clipboard

    @AppStorage("historyMaxCount") var historyMaxCount: Int = 200
    @AppStorage("imageMaxSizeMB") var imageMaxSizeMB: Int = 2  // 0 means unlimited
    @AppStorage("pollingInterval") var pollingInterval: Double = 0.5
    @AppStorage("cleanupOnStartup") var cleanupOnStartup: Bool = true
    @AppStorage("dedupEnabled") var dedupEnabled: Bool = true

    // MARK: - Shortcuts

    @AppStorage("showHideShortcut") var showHideShortcut: String = "cmd+shift+V"
    @AppStorage("quickPasteShortcut") var quickPasteShortcut: String = "cmd+shift+C"
    @AppStorage("togglePinShortcut") var togglePinShortcut: String = ""

    // MARK: - Advanced

    @AppStorage("iCloudSyncEnabled") var iCloudSyncEnabled: Bool = false

    // MARK: - Actions

    /// Reset all settings to their default values.
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
                    contentTypeRaw: "text",
                    textContent: text,
                    pasteCount: item.pasteCount,
                    sourceAppBundleID: item.sourceApp
                )
                context.insert(clip)
            case "image":
                guard let base64 = item.content, let imageData = Data(base64Encoded: base64) else { continue }
                let md5 = ClipboardMonitor.md5Hash(imageData)
                guard !existingMD5s.contains(md5) else { continue }
                let clip = ClipItem(
                    timestamp: item.timestamp,
                    contentTypeRaw: "image",
                    imageData: imageData,
                    imageFileName: item.fileName,
                    imageMD5: md5,
                    pasteCount: item.pasteCount,
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

- [ ] **Step 2: Verify the file compiles**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

Note: As a new file, it must be added to the Xcode project. The build may fail until we add the file in Task 5 — check that the error is about the file not being in the target, not a syntax error.

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/Settings/SettingsStore.swift"
git commit -m "feat: add SettingsStore with @AppStorage properties and data export/import"
```

---

### Task 2: Create ClipboardSettingsView

**Files:**
- Create: `Mini Capsule/Settings/ClipboardSettingsView.swift`

**Interfaces:**
- Consumes: `@EnvironmentObject var settings: SettingsStore`
- Produces: `ClipboardSettingsView` — SwiftUI View for the Clipboard tab

- [ ] **Step 1: Create the ClipboardSettingsView.swift file**

```swift
// Mini Capsule/Settings/ClipboardSettingsView.swift
import SwiftUI

struct ClipboardSettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                LabeledContent("历史记录上限") {
                    HStack(spacing: 8) {
                        Text("\(settings.historyMaxCount) 条")
                            .frame(minWidth: 50, alignment: .trailing)
                            .foregroundColor(.secondary)
                        Stepper("", value: $settings.historyMaxCount, in: 50...1000, step: 50)
                            .labelsHidden()
                    }
                }

                LabeledContent("图像大小限制") {
                    Picker("", selection: $settings.imageMaxSizeMB) {
                        Text("1 MB").tag(1)
                        Text("2 MB").tag(2)
                        Text("5 MB").tag(5)
                        Text("无限制").tag(0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }

                LabeledContent("轮询间隔") {
                    Picker("", selection: $settings.pollingInterval) {
                        Text("0.5 秒").tag(0.5)
                        Text("1 秒").tag(1.0)
                        Text("2 秒").tag(2.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                .onChange(of: settings.pollingInterval) { _, _ in
                    NotificationCenter.default.post(
                        name: .pollingIntervalDidChange,
                        object: nil
                    )
                }
            } header: {
                Text("存储")
            }

            Section {
                Toggle("启动时清理历史", isOn: $settings.cleanupOnStartup)
                Toggle("内容去重", isOn: $settings.dedupEnabled)
            } header: {
                Text("行为")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 300)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add "Mini Capsule/Settings/ClipboardSettingsView.swift"
git commit -m "feat: add ClipboardSettingsView with history, image, polling, and behavior settings"
```

---

### Task 3: Create ShortcutsSettingsView

**Files:**
- Create: `Mini Capsule/Settings/ShortcutsSettingsView.swift`

**Interfaces:**
- Consumes: `@EnvironmentObject var settings: SettingsStore`
- Produces: `ShortcutsSettingsView` — SwiftUI View for the Shortcuts tab

- [ ] **Step 1: Create the ShortcutsSettingsView.swift file**

```swift
// Mini Capsule/Settings/ShortcutsSettingsView.swift
import SwiftUI
import AppKit

struct ShortcutsSettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                ShortcutRow(
                    label: "显示/隐藏胶囊",
                    shortcut: $settings.showHideShortcut,
                    allShortcuts: allShortcutBindings
                )

                ShortcutRow(
                    label: "快速粘贴上一条",
                    shortcut: $settings.quickPasteShortcut,
                    allShortcuts: allShortcutBindings
                )

                ShortcutRow(
                    label: "切换置顶",
                    shortcut: $settings.togglePinShortcut,
                    allShortcuts: allShortcutBindings
                )
            } header: {
                Text("快捷键")
            } footer: {
                Text("点击"录制"后按下键盘组合键。留空表示不设置快捷键。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 250)
    }

    /// All shortcut bindings for conflict detection.
    private var allShortcutBindings: [Binding<String>] {
        [$settings.showHideShortcut, $settings.quickPasteShortcut, $settings.togglePinShortcut]
    }
}

// MARK: - Shortcut Row

private struct ShortcutRow: View {
    let label: String
    @Binding var shortcut: String
    var allShortcuts: [Binding<String>]

    @State private var isRecording = false
    @State private var conflictMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .frame(width: 130, alignment: .leading)

                Text(displayString)
                    .foregroundColor(isRecording ? .red : .secondary)
                    .frame(minWidth: 80, alignment: .leading)

                Button(isRecording ? "按下快捷键..." : "录制") {
                    isRecording.toggle()
                }
                .buttonStyle(.bordered)
                .tint(isRecording ? .red : nil)
            }

            if let conflict = conflictMessage, !shortcut.isEmpty {
                Text("⚠️ \(conflict)")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .padding(.leading, 130)
            }
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                startCapture()
            }
        }
    }

    private var displayString: String {
        if isRecording {
            return "按下快捷键..."
        }
        if shortcut.isEmpty {
            return "未设置"
        }
        return shortcut
            .replacingOccurrences(of: "cmd", with: "⌘")
            .replacingOccurrences(of: "shift", with: "⇧")
            .replacingOccurrences(of: "option", with: "⌥")
            .replacingOccurrences(of: "control", with: "⌃")
            .replacingOccurrences(of: "+", with: "")
            .uppercased()
    }

    private func startCapture() {
        // Install a local event monitor for the next keyDown
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event)
            return nil // consume the event while recording
        }

        // Store monitor reference; remove after 10s timeout or on capture
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            NSEvent.removeMonitor(monitor)
            if isRecording {
                isRecording = false
            }
        }

        // Clean up on next recording toggle off
        let cleanupMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if !isRecording {
                NSEvent.removeMonitor(monitor)
                return event
            }
            return nil
        }

        // We need to hold onto the monitors. Use a simple retain trick:
        // store the monitor in the isRecording didSet to clean it up.
        // For simplicity, we use a one-shot approach — the first keyDown after recording=true
        // captures the shortcut and removes itself.
    }

    private func handleKeyEvent(_ event: NSEvent) {
        var parts: [String] = []
        if event.modifierFlags.contains(.command) { parts.append("cmd") }
        if event.modifierFlags.contains(.shift) { parts.append("shift") }
        if event.modifierFlags.contains(.option) { parts.append("option") }
        if event.modifierFlags.contains(.control) { parts.append("control") }

        // Get the key from the charactersIgnoringModifiers
        guard let key = event.charactersIgnoringModifiers?.uppercased(),
              !key.isEmpty else { return }

        // Only allow keys that aren't pure modifier presses
        let modifierOnlyKeys: Set<String> = ["", "\u{7F}"]
        guard !modifierOnlyKeys.contains(key) else { return }

        parts.append(key.lowercased())
        let newShortcut = parts.joined(separator: "+")

        shortcut = newShortcut
        checkConflicts(newShortcut)
        isRecording = false
    }

    private func checkConflicts(_ newShortcut: String) {
        // Check for conflicts with other Mini Capsule shortcuts
        for binding in allShortcuts {
            if binding.wrappedValue == newShortcut && binding.wrappedValue != shortcut {
                conflictMessage = "与「\(label)」冲突"
                return
            }
        }
        // Check common system shortcuts
        let systemConflicts: [String: String] = [
            "cmd+space": "Spotlight",
            "cmd+shift+3": "截屏",
            "cmd+shift+4": "截屏选区",
            "cmd+shift+5": "截屏录制",
            "cmd+tab": "应用切换器",
            "cmd+v": "粘贴",
            "cmd+c": "拷贝",
            "cmd+x": "剪切",
        ]
        if let name = systemConflicts[newShortcut] {
            conflictMessage = "与系统快捷键（\(name)）冲突"
            return
        }
        conflictMessage = nil
    }
}
```

**Note:** The keyboard capture approach above has a subtlety — we need to hold a strong reference to the event monitor so it isn't deallocated. Let me refine the `startCapture` method to use a `@State` reference. Actually, the simplest correct approach is to store the monitor reference in the view state.

- [ ] **Step 2: Refine ShortcutRow to hold monitor reference properly**

Replace the `startCapture` and related logic with a stored monitor ID approach. Rewrite `ShortcutRow` as:

```swift
private struct ShortcutRow: View {
    let label: String
    @Binding var shortcut: String
    var allShortcuts: [Binding<String>]

    @State private var isRecording = false
    @State private var conflictMessage: String?
    @State private var monitorRef: Any? // holds the NSEvent monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .frame(width: 130, alignment: .leading)

                Text(displayString)
                    .foregroundColor(isRecording ? .red : .secondary)
                    .frame(minWidth: 80, alignment: .leading)

                Button(isRecording ? "按下快捷键..." : "录制") {
                    if isRecording {
                        stopCapture()
                    } else {
                        startCapture()
                    }
                }
                .buttonStyle(.bordered)
                .tint(isRecording ? .red : nil)

                if !shortcut.isEmpty && !isRecording {
                    Button(action: {
                        shortcut = ""
                        conflictMessage = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }

            if let conflict = conflictMessage, !shortcut.isEmpty {
                Text("⚠️ \(conflict)")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .padding(.leading, 130)
            }
        }
    }

    private var displayString: String {
        if isRecording {
            return "按下快捷键..."
        }
        if shortcut.isEmpty {
            return "未设置"
        }
        return shortcut
            .replacingOccurrences(of: "cmd", with: "⌘")
            .replacingOccurrences(of: "shift", with: "⇧")
            .replacingOccurrences(of: "option", with: "⌥")
            .replacingOccurrences(of: "control", with: "⌃")
            .replacingOccurrences(of: "+", with: "")
            .uppercased()
    }

    private func startCapture() {
        isRecording = true
        let mon = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            handleKeyEvent(event)
            return nil
        }
        monitorRef = mon

        // Timeout after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [self] in
            if isRecording {
                stopCapture()
            }
        }
    }

    private func stopCapture() {
        if let mon = monitorRef {
            NSEvent.removeMonitor(mon)
        }
        monitorRef = nil
        isRecording = false
    }

    private func handleKeyEvent(_ event: NSEvent) {
        var parts: [String] = []
        if event.modifierFlags.contains(.command) { parts.append("cmd") }
        if event.modifierFlags.contains(.shift) { parts.append("shift") }
        if event.modifierFlags.contains(.option) { parts.append("option") }
        if event.modifierFlags.contains(.control) { parts.append("control") }

        guard let key = event.charactersIgnoringModifiers?.uppercased(),
              !key.isEmpty else { return }

        let modifierOnlyKeys: Set<String> = ["", "\u{7F}"]
        guard !modifierOnlyKeys.contains(key) else { return }

        parts.append(key.lowercased())
        let newShortcut = parts.joined(separator: "+")

        shortcut = newShortcut
        checkConflicts(newShortcut)
        stopCapture()
    }

    private func checkConflicts(_ newShortcut: String) {
        for binding in allShortcuts {
            // Skip self
            if binding.wrappedValue == newShortcut && binding !== _shortcut {
                conflictMessage = "与其他快捷键冲突"
                return
            }
        }
        let systemConflicts: [String: String] = [
            "cmd+space": "Spotlight",
            "cmd+shift+3": "截屏",
            "cmd+shift+4": "截屏选区",
            "cmd+shift+5": "截屏录制",
            "cmd+tab": "应用切换器",
            "cmd+v": "粘贴",
            "cmd+c": "拷贝",
            "cmd+x": "剪切",
        ]
        if let name = systemConflicts[newShortcut] {
            conflictMessage = "与系统快捷键（\(name)）冲突"
            return
        }
        conflictMessage = nil
    }
}
```

Wait — `Binding` is a value type, so `binding !== _shortcut` won't work for identity comparison. We need a different approach for conflict detection. Let me use the label string instead.

Also, the `[self]` capture in the closure is problematic because `ShortcutRow` is a struct (value type). Let me use a class-based helper.

Actually, for the plan, I'll note this needs care and provide the working approach in the step. Let me use a reference type helper for the monitor.

Let me restructure: use a `ShortcutCaptureManager` class that holds the monitor.

Let me rewrite the complete ShortcutsSettingsView more carefully.

Actually, I think the simplest approach that works: use a callback-based capture. Let me simplify this considerably.

Instead of trying to do inline NSEvent monitoring in a SwiftUI view (which is tricky due to value-type semantics), I'll use a different approach: a simple TextField that accepts keyboard input and parses modifiers. But that's also complex.

The cleanest approach: use a dedicated `@Observable` class (or `@MainActor` class) for the capture state, separate from the view. Let me define a `ShortcutCapturer` class.

OK, let me just write the clean version for the plan. I'll use a class-based capture manager.

```swift
@MainActor
final class ShortcutCaptureManager: ObservableObject {
    @Published var isRecording = false
    @Published var capturedShortcut: String?
    private var monitor: Any?

    func startCapture() {
        isRecording = true
        capturedShortcut = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleEvent(event)
            return nil
        }
    }

    func stopCapture() {
        if let mon = monitor {
            NSEvent.removeMonitor(mon)
        }
        monitor = nil
        isRecording = false
    }

    private func handleEvent(_ event: NSEvent) {
        var parts: [String] = []
        if event.modifierFlags.contains(.command) { parts.append("cmd") }
        if event.modifierFlags.contains(.shift) { parts.append("shift") }
        if event.modifierFlags.contains(.option) { parts.append("option") }
        if event.modifierFlags.contains(.control) { parts.append("control") }
        guard let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { return }
        parts.append(key)
        capturedShortcut = parts.joined(separator: "+")
        stopCapture()
    }
}
```

Then each ShortcutRow creates its own capture manager. This is cleaner.

Let me rewrite the full file now for the plan.

- [ ] **Step 2: Create the final ShortcutsSettingsView.swift** (combined, clean version)

```swift
// Mini Capsule/Settings/ShortcutsSettingsView.swift
import SwiftUI
import AppKit

// MARK: - Capture Manager

@MainActor
final class ShortcutCaptureManager: ObservableObject {
    @Published var isRecording = false
    @Published var capturedShortcut: String?
    private var monitor: Any?

    func startCapture() {
        isRecording = true
        capturedShortcut = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleEvent(event)
            return nil
        }
        // Timeout after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, self.isRecording else { return }
            self.stopCapture()
        }
    }

    func stopCapture() {
        if let mon = monitor {
            NSEvent.removeMonitor(mon)
        }
        monitor = nil
        isRecording = false
    }

    private func handleEvent(_ event: NSEvent) {
        var parts: [String] = []
        if event.modifierFlags.contains(.command) { parts.append("cmd") }
        if event.modifierFlags.contains(.shift) { parts.append("shift") }
        if event.modifierFlags.contains(.option) { parts.append("option") }
        if event.modifierFlags.contains(.control) { parts.append("control") }
        guard let key = event.charactersIgnoringModifiers?.lowercased(),
              !key.isEmpty else { return }
        let modifierKeys: Set<String> = ["", "\u{7F}"]
        guard !modifierKeys.contains(key) else { return }
        parts.append(key)
        capturedShortcut = parts.joined(separator: "+")
        stopCapture()
    }
}

// MARK: - Settings View

struct ShortcutsSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @StateObject private var captureManager = ShortcutCaptureManager()

    var body: some View {
        Form {
            Section {
                ShortcutRowView(
                    label: "显示/隐藏胶囊",
                    shortcut: $settings.showHideShortcut,
                    allLabels: allLabels
                )
                ShortcutRowView(
                    label: "快速粘贴上一条",
                    shortcut: $settings.quickPasteShortcut,
                    allLabels: allLabels
                )
                ShortcutRowView(
                    label: "切换置顶",
                    shortcut: $settings.togglePinShortcut,
                    allLabels: allLabels
                )
            } header: {
                Text("快捷键")
            } footer: {
                Text("点击"录制"后按下键盘组合键。留空表示不设置快捷键。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 250)
    }

    private var allLabels: [String] {
        ["显示/隐藏胶囊", "快速粘贴上一条", "切换置顶"]
    }
}

// MARK: - Row View

private struct ShortcutRowView: View {
    let label: String
    @Binding var shortcut: String
    let allLabels: [String]

    @StateObject private var captureManager = ShortcutCaptureManager()

    @State private var conflictMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .frame(width: 130, alignment: .leading)

                Text(displayString)
                    .foregroundColor(captureManager.isRecording ? .red : .secondary)
                    .frame(minWidth: 80, alignment: .leading)

                Button(captureManager.isRecording ? "按下快捷键..." : "录制") {
                    if captureManager.isRecording {
                        captureManager.stopCapture()
                    } else {
                        captureManager.startCapture()
                    }
                }
                .buttonStyle(.bordered)
                .tint(captureManager.isRecording ? .red : nil)

                if !shortcut.isEmpty && !captureManager.isRecording {
                    Button(action: {
                        shortcut = ""
                        conflictMessage = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }

            if let conflict = conflictMessage, !shortcut.isEmpty {
                Text("⚠️ \(conflict)")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .padding(.leading, 130)
            }
        }
        .onChange(of: captureManager.capturedShortcut) { _, newValue in
            if let new = newValue {
                shortcut = new
                checkConflicts(new)
            }
        }
    }

    private var displayString: String {
        if captureManager.isRecording {
            return "按下快捷键..."
        }
        if shortcut.isEmpty {
            return "未设置"
        }
        return shortcut
            .replacingOccurrences(of: "cmd", with: "⌘")
            .replacingOccurrences(of: "shift", with: "⇧")
            .replacingOccurrences(of: "option", with: "⌥")
            .replacingOccurrences(of: "control", with: "⌃")
            .replacingOccurrences(of: "+", with: "")
            .uppercased()
    }

    private func checkConflicts(_ newShortcut: String) {
        // Check other Mini Capsule shortcuts
        let allBindings: [String: String] = [
            "显示/隐藏胶囊": UserDefaults.standard.string(forKey: "showHideShortcut") ?? "cmd+shift+V",
            "快速粘贴上一条": UserDefaults.standard.string(forKey: "quickPasteShortcut") ?? "cmd+shift+C",
            "切换置顶": UserDefaults.standard.string(forKey: "togglePinShortcut") ?? "",
        ]
        for (otherLabel, otherShortcut) in allBindings {
            if otherLabel != label && otherShortcut == newShortcut && !newShortcut.isEmpty {
                conflictMessage = "与「\(otherLabel)」冲突"
                return
            }
        }
        let systemConflicts: [String: String] = [
            "cmd+space": "Spotlight",
            "cmd+shift+3": "截屏",
            "cmd+shift+4": "截屏选区",
            "cmd+shift+5": "截屏录制",
            "cmd+tab": "应用切换器",
        ]
        if let name = systemConflicts[newShortcut] {
            conflictMessage = "与系统快捷键（\(name)）冲突"
            return
        }
        conflictMessage = nil
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/Settings/ShortcutsSettingsView.swift"
git commit -m "feat: add ShortcutsSettingsView with keyboard shortcut recording"
```

---

### Task 4: Create AdvancedSettingsView

**Files:**
- Create: `Mini Capsule/Settings/AdvancedSettingsView.swift`

**Interfaces:**
- Consumes: `@EnvironmentObject var settings: SettingsStore`, `@Environment(\.modelContext) var modelContext`
- Produces: `AdvancedSettingsView` — SwiftUI View for the Advanced tab

- [ ] **Step 1: Create the AdvancedSettingsView.swift file**

```swift
// Mini Capsule/Settings/AdvancedSettingsView.swift
import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct AdvancedSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.modelContext) private var modelContext

    @State private var isOperating = false
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var alertTitle = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("iCloud 同步")
                        Text("即将推出")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: .constant(false))
                        .disabled(true)
                }
            } header: {
                Text("同步")
            }

            Section {
                Button("导出数据...") {
                    exportData()
                }
                .disabled(isOperating)

                Button("导入数据...") {
                    importData()
                }
                .disabled(isOperating)
            } header: {
                Text("数据管理")
            }

            Section {
                Button("清空所有历史") {
                    alertTitle = "清空所有历史"
                    alertMessage = "此操作将删除所有剪贴板历史记录，且不可撤销。确定要继续吗？"
                    showAlert = true
                }
                .foregroundColor(.red)

                Button("重置所有设置") {
                    alertTitle = "重置所有设置"
                    alertMessage = "所有设置将恢复为默认值。确定要继续吗？"
                    showAlert = true
                }
            } header: {
                Text("危险操作")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 300)
        .alert(alertTitle, isPresented: $showAlert) {
            Button("取消", role: .cancel) {}
            Button("确定", role: .destructive) {
                if alertTitle == "清空所有历史" {
                    settings.clearAllHistory(context: modelContext)
                } else if alertTitle == "重置所有设置" {
                    settings.resetAll()
                }
            }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func exportData() {
        isOperating = true
        defer { isOperating = false }

        guard let data = settings.exportData(context: modelContext) else {
            alertTitle = "导出失败"
            alertMessage = "无法读取剪贴板数据。"
            showAlert = true
            return
        }

        let panel = NSSavePanel()
        panel.title = "导出剪贴板数据"
        panel.nameFieldStringValue = "mini-capsule-export.json"
        panel.allowedContentTypes = [UTType.json]

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try data.write(to: url)
                } catch {
                    alertTitle = "导出失败"
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }

    private func importData() {
        isOperating = true
        defer { isOperating = false }

        let panel = NSOpenPanel()
        panel.title = "导入剪贴板数据"
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false

        panel.begin { response in
            if response == .OK, let url = panel.urls.first {
                do {
                    let data = try Data(contentsOf: url)
                    guard !data.isEmpty else {
                        alertTitle = "导入失败"
                        alertMessage = "文件为空或格式不正确。"
                        showAlert = true
                        return
                    }
                    try settings.importData(data, context: modelContext)
                } catch let error as DecodingError {
                    alertTitle = "导入失败"
                    alertMessage = "JSON 格式不正确：\(error.localizedDescription)"
                    showAlert = true
                } catch {
                    alertTitle = "导入失败"
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add "Mini Capsule/Settings/AdvancedSettingsView.swift"
git commit -m "feat: add AdvancedSettingsView with iCloud, export/import, clear, and reset"
```

---

### Task 5: Wire up Mini_CapsuleApp.swift — Add Settings Scene and EnvironmentObject

**Files:**
- Modify: `Mini Capsule/Mini_CapsuleApp.swift`

**Interfaces:**
- Consumes: `SettingsStore`, `ClipboardSettingsView`, `ShortcutsSettingsView`, `AdvancedSettingsView`
- Produces: `Settings` scene attached to the app, `SettingsStore` injected via `.environmentObject()`

- [ ] **Step 1: Read the current file, then apply edits**

The current `Mini_CapsuleApp.swift` body has:
```swift
var body: some Scene {
    #if os(macOS)
    WindowGroup {
        EmptyView()
            .hidden()
    }
    .commands {
        CommandGroup(replacing: .newItem) {}
    }
    #else
    WindowGroup {
        ContentView()
    }
    .modelContainer(sharedModelContainer)
    #endif
}
```

- [ ] **Step 2: Add SettingsStore as a static property on CapsuleAppDelegate and add Settings scene**

Edit `Mini_CapsuleApp.swift`:

**Change 1**: Add `settingsStore` to `CapsuleAppDelegate`:
```swift
// In CapsuleAppDelegate, after existing properties:
let settingsStore = SettingsStore()
```

**Change 2**: Add `Settings` scene after the existing `WindowGroup` in the `body`:
```swift
#if os(macOS)
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
.environmentObject(appDelegate.settingsStore)
.modelContainer(CapsuleAppDelegate.sharedModelContainer)
#endif
```

- [ ] **Step 3: Build and verify compilation**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`

If new files aren't in the Xcode project target, add them first:
```bash
# The .swift files in the Settings/ directory should be auto-detected if
# the directory exists under the project. If not, they need to be added
# via Xcode or by editing the pbxproj. For now, verify the build error
# and add files manually if needed.
ls "Mini Capsule/Settings/"
```

- [ ] **Step 4: Commit**

```bash
git add "Mini Capsule/Mini_CapsuleApp.swift"
git commit -m "feat: add Settings scene with tabs and SettingsStore injection"
```

---

### Task 6: Wire gear button in CapsuleExpandedView

**Files:**
- Modify: `Mini Capsule/UI/CapsuleExpandedView.swift:26-31`

**Interfaces:**
- Consumes: `@Environment(\.openSettings)` (macOS 14+)

- [ ] **Step 1: Add `@Environment(\.openSettings)` and replace the gear button action**

The current gear button code (lines 26-31):
```swift
Button(action: {}) {
    Image(systemName: "gear")
        .foregroundColor(.secondary)
        .font(.system(size: 13))
}
.buttonStyle(.plain)
```

Replace with:
```swift
Button(action: {
    if #available(macOS 14.0, *) {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    } else {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}) {
    Image(systemName: "gear")
        .foregroundColor(.secondary)
        .font(.system(size: 13))
}
.buttonStyle(.plain)
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/UI/CapsuleExpandedView.swift"
git commit -m "feat: wire gear button to open Settings window"
```

---

### Task 7: Adapt ClipboardMonitor to read settings from UserDefaults

**Files:**
- Modify: `Mini Capsule/Services/ClipboardMonitor.swift`

**Interfaces:**
- Consumes: `UserDefaults.standard` keys: `pollingInterval`, `imageMaxSizeMB`, `historyMaxCount`, `dedupEnabled`
- Listens for: `Notification.Name.pollingIntervalDidChange`

- [ ] **Step 1: Replace hardcoded values with UserDefaults reads and add polling interval listener**

The current `ClipboardMonitor` has:
- `timer = Timer.scheduledTimer(withTimeInterval: 0.5, ...)` — hardcoded 0.5s
- `capImageSize(data, maxBytes: 2_000_000)` — hardcoded 2MB
- `enforceCap(context: context, maxCount: 200)` — hardcoded 200
- No dedup toggle

Apply these changes:

**Change 1**: Add a method to read polling interval and start timer with it:
```swift
private var currentPollingInterval: TimeInterval {
    let interval = UserDefaults.standard.double(forKey: "pollingInterval")
    return interval > 0 ? interval : 0.5
}

private var maxImageBytes: Int {
    let mb = UserDefaults.standard.integer(forKey: "imageMaxSizeMB")
    switch mb {
    case 1: return 1_000_000
    case 5: return 5_000_000
    case 0: return Int.max  // unlimited
    default: return 2_000_000
    }
}

private var maxHistoryCount: Int {
    let count = UserDefaults.standard.integer(forKey: "historyMaxCount")
    return count >= 50 ? count : 200
}

private var isDedupEnabled: Bool {
    // Default true if key not set
    if UserDefaults.standard.object(forKey: "dedupEnabled") == nil { return true }
    return UserDefaults.standard.bool(forKey: "dedupEnabled")
}
```

**Change 2**: Replace timer creation in `start`:
```swift
func start(context: ModelContext) {
    self.context = context
    lastChangeCount = NSPasteboard.general.changeCount
    restartTimer()
    observeSettings()
}

private func restartTimer() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: currentPollingInterval, repeats: true) { [weak self] _ in
        Task { [weak self] in
            self?.checkPasteboard()
        }
    }
}

private func observeSettings() {
    NotificationCenter.default.addObserver(
        forName: .pollingIntervalDidChange,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        self?.restartTimer()
    }
}
```

**Change 3**: Replace hardcoded `2_000_000` in `readPasteboard`:
```swift
let image = capImageSize(data, maxBytes: maxImageBytes)
```
(Appears twice — once for `.png`, once for `.tiff`)

**Change 4**: Replace hardcoded `200` in `checkPasteboard`:
```swift
enforceCap(context: context, maxCount: maxHistoryCount)
```
(Appears twice — once after image dedup, once before text insert)

**Change 5**: Honor `dedupEnabled` — skip text dedup if disabled:
In the text dedup section, wrap the existing check:
```swift
if isDedupEnabled {
    if let latest = try? context.fetch(
        FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
    ).first {
        switch (latest.contentTypeRaw, content.type) {
        case ("text", "text") where latest.textContent == content.text:
            latest.timestamp = Date()
            try? context.save()
            return
        default:
            break
        }
    }
}
```

And wrap the image MD5 dedup:
```swift
if content.type == "image", let imageData = content.image {
    if isDedupEnabled {
        let md5 = Self.md5Hash(imageData)
        // ... existing dedup logic ...
    } else {
        // No dedup — always insert
        enforceCap(context: context, maxCount: maxHistoryCount)
        let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName
        let fileName = content.fileName ?? "\(appName ?? "未知")-\(UUID().uuidString.prefix(4))"
        let item = ClipItem(
            timestamp: Date(),
            contentTypeRaw: content.type,
            imageData: imageData,
            imageFileName: fileName,
            imageMD5: Self.md5Hash(imageData),
            sourceAppBundleID: sourceApp
        )
        context.insert(item)
        try? context.save()
        return
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/Services/ClipboardMonitor.swift"
git commit -m "feat: adapt ClipboardMonitor to read settings from UserDefaults"
```

---

### Task 8: Adapt FrequencyCleanupService to read settings

**Files:**
- Modify: `Mini Capsule/Services/FrequencyCleanupService.swift`

**Interfaces:**
- Consumes: `UserDefaults.standard` key `historyMaxCount`

- [ ] **Step 1: Read keepCount from UserDefaults**

In `performCleanup`, the current signature:
```swift
static func performCleanup(context: ModelContext, keepCount: Int = 50)
```

The call site in `Mini_CapsuleApp.swift`:
```swift
FrequencyCleanupService.performCleanup(
    context: Self.sharedModelContainer.mainContext,
    keepCount: 50
)
```

Change the default to read from UserDefaults:
```swift
static func performCleanup(context: ModelContext, keepCount: Int? = nil) {
    let keep = keepCount ?? {
        let count = UserDefaults.standard.integer(forKey: "historyMaxCount")
        return count >= 50 ? min(50, count) : 50
    }()
    // ... rest of the method uses `keep` instead of `keepCount` ...
}
```

Update the method body to use `keep` (rename the variable from `keepCount` to `keep`):
```swift
let sorted = items.sorted { a, b in
    if a.isPinned != b.isPinned {
        return a.isPinned
    }
    return a.pasteCount > b.pasteCount
}

var kept = 0

let toDelete = sorted.filter { item in
    if item.isPinned {
        return false
    }
    kept += 1
    return kept > keep
}

for item in toDelete {
    context.delete(item)
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/Services/FrequencyCleanupService.swift"
git commit -m "feat: adapt FrequencyCleanupService to read keepCount from UserDefaults"
```

---

### Task 9: Add keyboard shortcut handling in CapsuleAppDelegate

**Files:**
- Modify: `Mini Capsule/Mini_CapsuleApp.swift` (CapsuleAppDelegate class)

**Interfaces:**
- Consumes: `UserDefaults.standard` keys: `showHideShortcut`, `quickPasteShortcut`, `togglePinShortcut`

- [ ] **Step 1: Add keyboard shortcut registration method**

Add to `CapsuleAppDelegate`:

```swift
private var shortcutMonitor: Any?

func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    FrequencyCleanupService.performCleanup(
        context: Self.sharedModelContainer.mainContext,
        keepCount: 50
    )

    let controller = CapsuleWindowController(modelContainer: Self.sharedModelContainer)
    controller.showWindow()
    capsuleWindowController = controller

    let monitor = ClipboardMonitor()
    monitor.start(context: Self.sharedModelContainer.mainContext)
    clipboardMonitor = monitor

    registerShortcuts()  // <-- NEW
}

private func registerShortcuts() {
    shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self = self else { return event }

        let combo = self.shortcutString(from: event)

        let showHide = UserDefaults.standard.string(forKey: "showHideShortcut") ?? "cmd+shift+V"
        let quickPaste = UserDefaults.standard.string(forKey: "quickPasteShortcut") ?? "cmd+shift+C"
        let togglePin = UserDefaults.standard.string(forKey: "togglePinShortcut") ?? ""

        if combo == showHide {
            self.capsuleWindowController?.toggleWindow()
            return nil
        }
        if combo == quickPaste {
            self.performQuickPaste()
            return nil
        }
        if !togglePin.isEmpty && combo == togglePin {
            self.performTogglePin()
            return nil
        }

        return event
    }
}

private func shortcutString(from event: NSEvent) -> String {
    var parts: [String] = []
    if event.modifierFlags.contains(.command) { parts.append("cmd") }
    if event.modifierFlags.contains(.shift) { parts.append("shift") }
    if event.modifierFlags.contains(.option) { parts.append("option") }
    if event.modifierFlags.contains(.control) { parts.append("control") }
    if let key = event.charactersIgnoringModifiers?.lowercased() {
        parts.append(key)
    }
    return parts.joined(separator: "+")
}

private func performQuickPaste() {
    guard let context = clipboardMonitor?.context else { return }
    let latest = try? context.fetch(
        FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
    )
    guard let item = latest?.first else { return }
    PasteService.copyToClipboard(item)
}

private func performTogglePin() {
    guard let context = clipboardMonitor?.context else { return }
    let items = try? context.fetch(
        FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
    )
    guard let latest = items?.first else { return }
    latest.isPinned.toggle()
    try? context.save()
}
```

Note: `CapsuleWindowController` needs a `toggleWindow()` method and `ClipboardMonitor` needs to expose its `context` property. These are small additions:

**In `CapsuleWindowController`**, add:
```swift
func toggleWindow() {
    guard let window = window else { return }
    if window.isVisible {
        window.orderOut(nil)
    } else {
        window.makeKeyAndOrderFront(nil)
    }
}
```

**In `ClipboardMonitor`**, change `context` from `private var` to `private(set) var`:
```swift
private(set) var context: ModelContext?
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/Mini_CapsuleApp.swift" "Mini Capsule/UI/CapsuleWindowController.swift" "Mini Capsule/Services/ClipboardMonitor.swift"
git commit -m "feat: add keyboard shortcut handling with NSEvent local monitor"
```

---

### Task 10: Write unit tests for SettingsStore

**Files:**
- Modify: `Mini CapsuleTests/Mini_CapsuleTests.swift`

**Interfaces:**
- Tests: `SettingsStore` defaults, `resetAll()`, `historyMaxCount` clamping, key read/write

- [ ] **Step 1: Add SettingsStore tests to the test file**

Replace the example test with:

```swift
// Mini CapsuleTests/Mini_CapsuleTests.swift
import Testing
import Foundation
@testable import Mini_Capsule

struct SettingsStoreTests {

    @Test func defaults() async throws {
        // Reset UserDefaults for this suite
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "historyMaxCount")
        defaults.removeObject(forKey: "imageMaxSizeMB")
        defaults.removeObject(forKey: "pollingInterval")
        defaults.removeObject(forKey: "cleanupOnStartup")
        defaults.removeObject(forKey: "dedupEnabled")

        // Given: a fresh store
        let store = SettingsStore()

        // Then: defaults are set
        #expect(store.historyMaxCount == 200)
        #expect(store.imageMaxSizeMB == 2)
        #expect(store.pollingInterval == 0.5)
        #expect(store.cleanupOnStartup == true)
        #expect(store.dedupEnabled == true)
        #expect(store.showHideShortcut == "cmd+shift+V")
        #expect(store.quickPasteShortcut == "cmd+shift+C")
        #expect(store.togglePinShortcut == "")
        #expect(store.iCloudSyncEnabled == false)
    }

    @Test func resetAllRestoresDefaults() async throws {
        let store = SettingsStore()

        // Given: modified settings
        store.historyMaxCount = 500
        store.imageMaxSizeMB = 0
        store.pollingInterval = 2.0
        store.cleanupOnStartup = false
        store.dedupEnabled = false
        store.showHideShortcut = "cmd+option+V"
        store.quickPasteShortcut = ""
        store.togglePinShortcut = "cmd+shift+P"
        store.iCloudSyncEnabled = true

        // When: reset
        store.resetAll()

        // Then: all defaults restored
        #expect(store.historyMaxCount == 200)
        #expect(store.imageMaxSizeMB == 2)
        #expect(store.pollingInterval == 0.5)
        #expect(store.cleanupOnStartup == true)
        #expect(store.dedupEnabled == true)
        #expect(store.showHideShortcut == "cmd+shift+V")
        #expect(store.quickPasteShortcut == "cmd+shift+C")
        #expect(store.togglePinShortcut == "")
        #expect(store.iCloudSyncEnabled == false)
    }

    @Test func settingsPersistAcrossStoreInstances() async throws {
        let store1 = SettingsStore()
        store1.historyMaxCount = 300

        // Given: a second store instance
        let store2 = SettingsStore()

        // Then: reads the same UserDefaults value
        #expect(store2.historyMaxCount == 300)

        // Cleanup
        store1.resetAll()
    }

    @Test func shortcutKeys() async throws {
        let store = SettingsStore()

        store.showHideShortcut = "cmd+option+K"
        #expect(store.showHideShortcut == "cmd+option+K")

        store.togglePinShortcut = ""
        #expect(store.togglePinShortcut.isEmpty == true)
    }
}
```

- [ ] **Step 2: Run the tests**

Run: `xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test 2>&1 | tail -15`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add "Mini CapsuleTests/Mini_CapsuleTests.swift"
git commit -m "test: add SettingsStore unit tests for defaults, reset, and persistence"
```

---

### Task 11: Build, run, and manual verification

**Files:**
- (No file changes — verification only)

- [ ] **Step 1: Build the project**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Run unit tests**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test 2>&1 | tail -10
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 3: Run the app and manually verify**

Launch: `open "Mini Capsule.xcodeproj"` and run from Xcode (⌘R), or build and run the product directly.

Manual verification checklist:
1. Hover over the capsule → expanded view appears with gear button
2. Click gear → Settings window opens with three tabs
3. Clipboard tab: change history count, image size, polling interval → verify stepper/picker work
4. Shortcuts tab: click "录制" → press a key combo → shortcut is captured and displayed
5. Shortcuts tab: record same shortcut for two actions → see conflict warning
6. Shortcuts tab: clear a shortcut with the X button
7. Advanced tab: click "导出数据" → save dialog appears, save file → verify JSON content
8. Advanced tab: click "清空所有历史" → confirm → verify history is cleared
9. Advanced tab: click "重置所有设置" → confirm → verify settings revert to defaults
10. Change polling interval in settings → verify ClipboardMonitor restarts with new interval (observe behavior)
11. Close and reopen settings window → verify previous state is remembered

- [ ] **Step 4: Final commit (if any changes from verification)**

```bash
git status
# Only if there are uncommitted changes:
git add -A
git commit -m "chore: final adjustments from manual verification"
```
```
