# Appearance & General Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add General and Appearance settings tabs, menu bar support, dot collapse style, unfocused opacity, and background image for the capsule panel.

**Architecture:** New `MenuBarService` manages NSStatusItem. `GeneralSettingsView` and `AppearanceSettingsView` are new Form-based tabs. `CapsuleWindowController` gets dynamic collapsed size. `CapsuleCollapsedView` gains a dot variant. `CapsuleView` reads configurable delays and applies opacity. `SettingsStore` gets 10 new @AppStorage keys.

**Tech Stack:** SwiftUI, SwiftData, AppKit (NSStatusItem, NSMenu, NSOpenPanel, SMAppService)

## Global Constraints

- Deployment target: macOS 26.5
- Chinese (Simplified) labels for all UI text
- Use `@AppStorage` for all persisted settings
- Follow existing project patterns: `// Mini Capsule/Path/File.swift` header comments
- `Form` + `.formStyle(.grouped)` for settings tabs
- New keys must be added to `resetAll()` in SettingsStore
- Both-toggles-off edge case: warn and auto-enable menu bar

---

### Task 1: Add new @AppStorage keys to SettingsStore

**Files:**
- Modify: `Mini Capsule/Settings/SettingsStore.swift`

**Interfaces:**
- Produces: 10 new @AppStorage properties: `launchAtLogin`, `showInMenuBar`, `showFloatingPanel`, `collapsedStyle`, `hoverExpandDelay`, `hoverCollapseDelay`, `panelOpacityUnfocused`, `backgroundImageData`, `dotColorMode`, `dotCustomColor`; updated `resetAll()`

- [ ] **Step 1: Add new keys and update resetAll()**

Add after the Advanced section (after line 41):

```swift
    // MARK: - General

    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("showInMenuBar") var showInMenuBar: Bool = true
    @AppStorage("showFloatingPanel") var showFloatingPanel: Bool = true
    @AppStorage("collapsedStyle") var collapsedStyle: String = "capsule"
    @AppStorage("hoverExpandDelay") var hoverExpandDelay: Double = 0.3
    @AppStorage("hoverCollapseDelay") var hoverCollapseDelay: Double = 1.0

    // MARK: - Appearance

    @AppStorage("panelOpacityUnfocused") var panelOpacityUnfocused: Double = 0.6
    @AppStorage("backgroundImageData") var backgroundImageData: Data? = nil
    @AppStorage("dotColorMode") var dotColorMode: String = "auto"
    @AppStorage("dotCustomColor") var dotCustomColor: String = "#007AFF"
```

Update `resetAll()` to include new keys:

```swift
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
        backgroundImageData = nil
        dotColorMode = "auto"
        dotCustomColor = "#007AFF"
    }
```

- [ ] **Step 2: Build and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
# Expected: ** BUILD SUCCEEDED **

git add "Mini Capsule/Settings/SettingsStore.swift"
git commit -m "feat: add general and appearance @AppStorage keys to SettingsStore"
```

---

### Task 2: Create GeneralSettingsView

**Files:**
- Create: `Mini Capsule/Settings/GeneralSettingsView.swift`

**Interfaces:**
- Consumes: `@EnvironmentObject var settings: SettingsStore`
- Produces: `GeneralSettingsView` — SwiftUI View for the General tab

- [ ] **Step 1: Create GeneralSettingsView.swift**

```swift
// Mini Capsule/Settings/GeneralSettingsView.swift
import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("开机启动", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            settings.launchAtLogin = !newValue
                        }
                    }

                Toggle("菜单栏显示", isOn: $settings.showInMenuBar)
                    .onChange(of: settings.showInMenuBar) { _, _ in
                        ensureOneModeEnabled()
                    }

                Toggle("屏幕悬浮窗", isOn: $settings.showFloatingPanel)
                    .onChange(of: settings.showFloatingPanel) { _, newValue in
                        ensureOneModeEnabled()
                        if newValue {
                            NotificationCenter.default.post(
                                name: .showFloatingPanelChanged,
                                object: nil,
                                userInfo: ["show": true]
                            )
                        } else {
                            NotificationCenter.default.post(
                                name: .showFloatingPanelChanged,
                                object: nil,
                                userInfo: ["show": false]
                            )
                        }
                    }
            } header: {
                Text("展示")
            }

            Section {
                LabeledContent("折叠形态") {
                    Picker("", selection: $settings.collapsedStyle) {
                        Text("胶囊").tag("capsule")
                        Text("圆点").tag("dot")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                .disabled(!settings.showFloatingPanel)

                LabeledContent("悬停展开延迟") {
                    Picker("", selection: $settings.hoverExpandDelay) {
                        Text("0.1 秒").tag(0.1)
                        Text("0.3 秒").tag(0.3)
                        Text("0.5 秒").tag(0.5)
                        Text("1.0 秒").tag(1.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                .disabled(!settings.showFloatingPanel)

                LabeledContent("离开折叠延迟") {
                    Picker("", selection: $settings.hoverCollapseDelay) {
                        Text("0.5 秒").tag(0.5)
                        Text("1.0 秒").tag(1.0)
                        Text("2.0 秒").tag(2.0)
                        Text("3.0 秒").tag(3.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                .disabled(!settings.showFloatingPanel)
            } header: {
                Text("悬浮窗行为")
            }

            if !settings.showInMenuBar && !settings.showFloatingPanel {
                Text("⚠️ 至少需要开启一种展示方式")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 320)
    }

    private func ensureOneModeEnabled() {
        if !settings.showInMenuBar && !settings.showFloatingPanel {
            settings.showInMenuBar = true
        }
    }
}
```

- [ ] **Step 2: Add notification name to SettingsStore.swift**

Add after the existing `pollingIntervalDidChange` extension:

```swift
extension Notification.Name {
    static let pollingIntervalDidChange = Notification.Name("SettingsPollingIntervalDidChange")
    static let showFloatingPanelChanged = Notification.Name("ShowFloatingPanelChanged")
}
```

- [ ] **Step 3: Build and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
git add "Mini Capsule/Settings/GeneralSettingsView.swift" "Mini Capsule/Settings/SettingsStore.swift"
git commit -m "feat: add GeneralSettingsView with display mode, collapse style, and delay settings"
```

---

### Task 3: Create AppearanceSettingsView

**Files:**
- Create: `Mini Capsule/Settings/AppearanceSettingsView.swift`

**Interfaces:**
- Consumes: `@EnvironmentObject var settings: SettingsStore`
- Produces: `AppearanceSettingsView` — SwiftUI View for the Appearance tab

- [ ] **Step 1: Create AppearanceSettingsView.swift**

```swift
// Mini Capsule/Settings/AppearanceSettingsView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AppearanceSettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    @State private var thumbnailImage: NSImage?
    @State private var isChoosingImage = false

    var body: some View {
        Form {
            Section {
                LabeledContent("失焦不透明度") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.panelOpacityUnfocused, in: 0.3...1.0, step: 0.05)
                            .frame(width: 150)
                        Text(String(format: "%.0f%%", settings.panelOpacityUnfocused * 100))
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                Text("透明度")
            } footer: {
                Text("悬浮窗未聚焦或鼠标未悬停时的透明度。聚焦时始终不透明。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("展开面板背景图")
                        if let image = thumbnailImage {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            Text("未设置")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button("选择图片...") {
                        chooseImage()
                    }
                }

                if settings.backgroundImageData != nil {
                    Button("清除背景图") {
                        settings.backgroundImageData = nil
                        thumbnailImage = nil
                    }
                    .foregroundColor(.red)
                }
            } header: {
                Text("背景")
            }

            Section {
                LabeledContent("圆点颜色模式") {
                    Picker("", selection: $settings.dotColorMode) {
                        Text("自动").tag("auto")
                        Text("自定义").tag("custom")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                if settings.dotColorMode == "custom" {
                    LabeledContent("自定义颜色") {
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: settings.dotCustomColor) ?? .blue },
                            set: { settings.dotCustomColor = $0.toHex() }
                        ))
                        .frame(width: 60)
                    }
                }
            } header: {
                Text("圆点")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 320)
        .onAppear {
            if let data = settings.backgroundImageData {
                thumbnailImage = NSImage(data: data)
            }
        }
        .onChange(of: settings.backgroundImageData) { _, newData in
            if let data = newData {
                thumbnailImage = NSImage(data: data)
            } else {
                thumbnailImage = nil
            }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = "选择背景图片"
        panel.allowedContentTypes = [UTType.image]
        panel.allowsMultipleSelection = false

        panel.begin { response in
            if response == .OK, let url = panel.urls.first,
               let imageData = try? Data(contentsOf: url) {
                // Compress if over 2MB
                let compressed = capImageSize(imageData, maxBytes: 2_000_000)
                settings.backgroundImageData = compressed
            }
        }
    }

    private func capImageSize(_ data: Data, maxBytes: Int) -> Data {
        guard data.count > maxBytes,
              let image = NSImage(data: data) else { return data }
        let scale = sqrt(Double(maxBytes) / Double(data.count))
        let newSize = NSSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        else { return data }
        return jpeg
    }
}

// MARK: - Color Extensions

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        guard hex.count == 6,
              let num = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: Double((num >> 16) & 0xFF) / 255.0,
            green: Double((num >> 8) & 0xFF) / 255.0,
            blue: Double(num & 0xFF) / 255.0
        )
    }

    func toHex() -> String {
        guard let components = NSColor(self).cgColor.components, components.count >= 3 else {
            return "#007AFF"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
git add "Mini Capsule/Settings/AppearanceSettingsView.swift"
git commit -m "feat: add AppearanceSettingsView with opacity, background image, and dot color"
```

---

### Task 4: Create MenuBarService

**Files:**
- Create: `Mini Capsule/Services/MenuBarService.swift`

**Interfaces:**
- Consumes: `ModelContext` (for querying recent items), `SettingsStore` (for menu bar toggle)
- Produces: `MenuBarService` class — manages NSStatusItem, builds NSMenu with recent items

- [ ] **Step 1: Create MenuBarService.swift**

```swift
// Mini Capsule/Services/MenuBarService.swift
import AppKit
import SwiftUI
import SwiftData

@MainActor
final class MenuBarService: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var context: ModelContext?
    private var menu: NSMenu?

    func start(context: ModelContext) {
        self.context = context
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "📋"
        statusItem = item

        rebuildMenu()
        statusItem?.button?.action = nil
        statusItem?.button?.sendAction(on: [.leftMouseDown])

        // Use mouseDown to show menu
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self,
                  let button = self.statusItem?.button,
                  event.window == button.window else { return event }
            self.rebuildMenu()
            self.statusItem?.menu = self.menu
            button.performClick(nil)
            self.statusItem?.menu = nil
            return nil
        }

        // Observe clipboard changes to refresh menu
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Refresh menu on next open
        }
    }

    func stop() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    func updateVisibility(_ visible: Bool) {
        statusItem?.isVisible = visible
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        guard let context = context else { return }

        let showFloating = UserDefaults.standard.bool(forKey: "showFloatingPanel")

        // Recent items
        let descriptor = FetchDescriptor<ClipItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let recentItems = (try? context.fetch(descriptor))?.prefix(5) ?? []

        for item in recentItems {
            let preview = previewText(for: item)
            let menuItem = NSMenuItem(title: preview, action: #selector(menuItemClicked(_:)), keyEquivalent: "")
            menuItem.representedObject = item
            menuItem.target = self
            menu.addItem(menuItem)
        }

        if !recentItems.isEmpty {
            menu.addItem(.separator())
        }

        // Toggle floating panel
        let toggleTitle = showFloating ? "隐藏悬浮窗" : "打开悬浮窗"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleFloatingPanel), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        // Settings
        let settingsItem = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "退出 Mini Capsule", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.menu = menu
    }

    private func previewText(for item: ClipItem) -> String {
        switch item.contentTypeRaw {
        case "text":
            let text = item.textContent?.prefix(30).replacingOccurrences(of: "\n", with: " ") ?? ""
            return "📝 \(text)"
        case "image":
            return "🖼️ \(item.imageFileName ?? "图片")"
        case "file":
            return "📁 文件"
        default:
            return "未知"
        }
    }

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ClipItem else { return }
        PasteService.copyToClipboard(item)
        item.pasteCount += 1
        item.lastPastedAt = Date()
        try? context?.save()
    }

    @objc private func toggleFloatingPanel() {
        let current = UserDefaults.standard.bool(forKey: "showFloatingPanel")
        UserDefaults.standard.set(!current, forKey: "showFloatingPanel")
        NotificationCenter.default.post(
            name: .showFloatingPanelChanged,
            object: nil,
            userInfo: ["show": !current]
        )
    }

    @objc private func openSettings() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
git add "Mini Capsule/Services/MenuBarService.swift"
git commit -m "feat: add MenuBarService with NSStatusItem and recent items menu"
```

---

### Task 5: Update CapsuleWindowController — dynamic collapsed size

**Files:**
- Modify: `Mini Capsule/UI/CapsuleWindowController.swift`

**Interfaces:**
- Consumes: `UserDefaults.standard` key `collapsedStyle`
- Produces: dynamic `collapsedSize`, listener for `showFloatingPanelChanged` notification

- [ ] **Step 1: Make collapsedSize dynamic and observe showFloatingPanel**

Replace line 10:
```swift
private static let collapsedSize = NSSize(width: 200, height: 36)
```

With:
```swift
private static let capsuleCollapsedSize = NSSize(width: 200, height: 36)
private static let dotCollapsedSize = NSSize(width: 12, height: 12)

private var currentCollapsedSize: NSSize {
    let style = UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
    return style == "dot" ? Self.dotCollapsedSize : Self.capsuleCollapsedSize
}
```

Update `loadFrame()` — replace `collapsedSize` with `currentCollapsedSize` (the method reads `collapsedSize` but it's now dynamic; we need to adjust). Actually, `loadFrame()` is `static` — we need to read from UserDefaults there too:

```swift
private static func loadFrame() -> NSRect {
    let style = UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
    let size = style == "dot" ? dotCollapsedSize : capsuleCollapsedSize

    guard let screen = NSScreen.main else {
        return NSRect(x: 0, y: 0, width: size.width, height: size.height)
    }
    let screenWidth = screen.visibleFrame.width
    let screenHeight = screen.visibleFrame.maxY

    var x = (screenWidth - size.width) / 2
    var y = screenHeight - size.height - 40

    if let dict = UserDefaults.standard.dictionary(forKey: frameKey) as? [String: CGFloat],
       let savedX = dict["x"], let savedY = dict["y"] {
        let screenFrame = screen.visibleFrame
        let clampedX = min(max(savedX, screenFrame.minX), screenFrame.maxX - size.width)
        let clampedY = min(max(savedY, screenFrame.minY), screenFrame.maxY - size.height)
        x = clampedX
        y = clampedY
    }

    return NSRect(x: x, y: y, width: size.width, height: size.height)
}
```

Update `observeExpandedState()` — replace `Self.collapsedSize` with `currentCollapsedSize`:

```swift
private func observeExpandedState() {
    NotificationCenter.default.addObserver(
        forName: .capsuleDidChangeExpanded,
        object: nil,
        queue: .main
    ) { [weak self] notification in
        guard let self = self,
              let window = self.window,
              let isExpanded = notification.userInfo?["isExpanded"] as? Bool else { return }

        let collapsedSize = self.currentCollapsedSize
        let targetSize = isExpanded ? Self.expandedSize : collapsedSize
        let currentFrame = window.frame

        let newFrame = NSRect(
            x: currentFrame.midX - targetSize.width / 2,
            y: currentFrame.maxY - targetSize.height,
            width: targetSize.width,
            height: targetSize.height
        )

        window.setFrame(newFrame, display: true, animate: true)
    }

    // Listen for collapsed style changes
    NotificationCenter.default.addObserver(
        forName: UserDefaults.didChangeNotification,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        guard let self = self, let window = self.window else { return }
        // If currently collapsed, resize to new collapsed size
        // (expanded state is managed by CapsuleView hover logic)
    }

    // Listen for show floating panel toggle
    NotificationCenter.default.addObserver(
        forName: .showFloatingPanelChanged,
        object: nil,
        queue: .main
    ) { [weak self] notification in
        guard let self = self,
              let window = self.window,
              let show = notification.userInfo?["show"] as? Bool else { return }
        if show {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderOut(nil)
        }
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
git add "Mini Capsule/UI/CapsuleWindowController.swift"
git commit -m "feat: add dynamic collapsed size and show/hide listener to CapsuleWindowController"
```

---

### Task 6: Update CapsuleCollapsedView — dot variant

**Files:**
- Modify: `Mini Capsule/UI/CapsuleCollapsedView.swift`

**Interfaces:**
- Consumes: `collapsedStyle: String` parameter, `dotColorMode` and `dotCustomColor` from UserDefaults
- Produces: dot or capsule rendering based on style

- [ ] **Step 1: Add collapsedStyle parameter and dot variant**

Replace the entire file:

```swift
// Mini Capsule/UI/CapsuleCollapsedView.swift
import SwiftUI

struct CapsuleCollapsedView: View {
    let latestItem: ClipItem?
    let isCapturing: Bool
    let isDragPrimed: Bool
    let collapsedStyle: String

    var body: some View {
        if collapsedStyle == "dot" {
            dotView
        } else {
            capsuleView
        }
    }

    // MARK: - Dot variant

    private var dotView: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 12, height: 12)
            .scaleEffect(isCapturing ? 1.3 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: isCapturing)
            .background {
                if isDragPrimed {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 18, height: 18)
                }
            }
            .shadow(
                color: isDragPrimed ? .white.opacity(0.3) : .black.opacity(0.15),
                radius: isDragPrimed ? 6 : 4,
                y: isDragPrimed ? 0 : 2
            )
            .animation(.easeInOut(duration: 0.2), value: isDragPrimed)
    }

    private var dotColor: Color {
        let mode = UserDefaults.standard.string(forKey: "dotColorMode") ?? "auto"
        if mode == "custom" {
            let hex = UserDefaults.standard.string(forKey: "dotCustomColor") ?? "#007AFF"
            return Color(hex: hex) ?? .blue
        }
        guard let item = latestItem else { return .gray }
        switch item.contentTypeRaw {
        case "text": return .green
        case "image": return .blue
        case "file": return .orange
        default: return .gray
        }
    }

    // MARK: - Capsule variant (existing)

    private var capsuleView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isCapturing ? Color.blue : Color.green)
                .frame(width: 8, height: 8)
                .scaleEffect(isCapturing ? 1.3 : 1.0)
                .animation(.easeInOut(duration: 0.3), value: isCapturing)

            Text(summaryText)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(width: 200, height: 36)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                if isDragPrimed {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                }
            }
        }
        .clipShape(Capsule())
        .shadow(
            color: isDragPrimed ? .white.opacity(0.3) : .black.opacity(0.15),
            radius: isDragPrimed ? 6 : 8,
            y: isDragPrimed ? 0 : 4
        )
        .animation(.easeInOut(duration: 0.2), value: isDragPrimed)
    }

    private var summaryText: String {
        guard let item = latestItem else { return "等待复制..." }
        switch item.contentTypeRaw {
        case "text":
            return item.textContent?.prefix(20).replacingOccurrences(of: "\n", with: " ") ?? ""
        case "image":
            return "🖼️ 图片"
        case "file":
            return "📁 文件"
        default:
            return ""
        }
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
git add "Mini Capsule/UI/CapsuleCollapsedView.swift"
git commit -m "feat: add dot variant to CapsuleCollapsedView with color modes"
```

---

### Task 7: Update CapsuleView — configurable delays + opacity + collapsed style

**Files:**
- Modify: `Mini Capsule/UI/CapsuleView.swift`

**Interfaces:**
- Consumes: UserDefaults keys for delays and opacity, `collapsedStyle`
- Produces: Configurable hover behavior, opacity effect, passes collapsedStyle to collapsed view

- [ ] **Step 1: Apply changes**

Read the current file and apply these changes:

**Change 1:** Replace hardcoded delays with UserDefaults reads:

Find the hover timer blocks:
```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)  // hover expand
DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)  // hover collapse
```

Replace with:
```swift
let expandDelay = UserDefaults.standard.double(forKey: "hoverExpandDelay")
let effectiveExpandDelay = expandDelay > 0 ? expandDelay : 0.3
DispatchQueue.main.asyncAfter(deadline: .now() + effectiveExpandDelay, execute: workItem)

let collapseDelay = UserDefaults.standard.double(forKey: "hoverCollapseDelay")
let effectiveCollapseDelay = collapseDelay > 0 ? collapseDelay : 1.0
DispatchQueue.main.asyncAfter(deadline: .now() + effectiveCollapseDelay, execute: workItem)
```

**Change 2:** Add opacity modifier to the Group:

After `.simultaneousGesture(windowDragGesture)`, add:
```swift
.opacity(windowOpacity)
.animation(.easeInOut(duration: 0.3), value: windowOpacity)
```

And add the computed property:
```swift
private var windowOpacity: Double {
    let unfocusedOpacity = UserDefaults.standard.double(forKey: "panelOpacityUnfocused")
    let effectiveUnfocused = unfocusedOpacity > 0 ? unfocusedOpacity : 0.6
    // If expanded (hovering), fully opaque. Otherwise use unfocused setting.
    return isExpanded ? 1.0 : effectiveUnfocused
}
```

**Change 3:** Pass collapsedStyle to CapsuleCollapsedView:

Find:
```swift
CapsuleCollapsedView(
    latestItem: items.first,
    isCapturing: isCapturing,
    isDragPrimed: isDragPrimed
)
```

Replace with:
```swift
CapsuleCollapsedView(
    latestItem: items.first,
    isCapturing: isCapturing,
    isDragPrimed: isDragPrimed,
    collapsedStyle: UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
)
```

- [ ] **Step 2: Build and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
git add "Mini Capsule/UI/CapsuleView.swift"
git commit -m "feat: add configurable delays, opacity, and collapsed style to CapsuleView"
```

---

### Task 8: Update CapsuleExpandedView — background image support

**Files:**
- Modify: `Mini Capsule/UI/CapsuleExpandedView.swift`

**Interfaces:**
- Consumes: `backgroundImageData` from UserDefaults
- Produces: background image layer behind ultraThinMaterial

- [ ] **Step 1: Add background image layer**

In the `.background { }` block of CapsuleExpandedView, add an image layer before the Rectangle:

Find:
```swift
.background {
    ZStack {
        Rectangle()
            .fill(.ultraThinMaterial)
        if isDragPrimed {
            Rectangle()
                .fill(Color.white.opacity(0.1))
        }
    }
}
```

Replace with:
```swift
.background {
    ZStack {
        // Background image (if set)
        if let imageData = UserDefaults.standard.data(forKey: "backgroundImageData"),
           let nsImage = NSImage(data: imageData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }

        Rectangle()
            .fill(.ultraThinMaterial)

        if isDragPrimed {
            Rectangle()
                .fill(Color.white.opacity(0.1))
        }
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
git add "Mini Capsule/UI/CapsuleExpandedView.swift"
git commit -m "feat: add background image support to CapsuleExpandedView"
```

---

### Task 9: Wire up Mini_CapsuleApp — menu bar + new Settings tabs

**Files:**
- Modify: `Mini Capsule/Mini_CapsuleApp.swift`

**Interfaces:**
- Consumes: `MenuBarService`, `GeneralSettingsView`, `AppearanceSettingsView`
- Produces: Menu bar initialization, new tabs in Settings scene

- [ ] **Step 1: Add MenuBarService to CapsuleAppDelegate and wire new tabs**

**Change 1:** Add menuBarService property:
```swift
private var menuBarService: MenuBarService?
```

**Change 2:** In `applicationDidFinishLaunching`, after clipboard monitor start, add:
```swift
// Start menu bar
let menuBar = MenuBarService()
menuBar.start(context: Self.sharedModelContainer.mainContext)
menuBarService = menuBar
```

**Change 3:** In `applicationWillTerminate`, add:
```swift
menuBarService?.stop()
```

**Change 4:** In the Settings scene TabView, add the two new tabs before the existing three:
```swift
Settings {
    TabView {
        GeneralSettingsView()
            .tabItem { Label("通用", systemImage: "gear") }
        AppearanceSettingsView()
            .tabItem { Label("外观", systemImage: "paintpalette") }
        ClipboardSettingsView()
            .tabItem { Label("剪贴板", systemImage: "doc.on.clipboard") }
        ShortcutsSettingsView()
            .tabItem { Label("快捷键", systemImage: "command") }
        AdvancedSettingsView()
            .tabItem { Label("高级", systemImage: "ellipsis.curlybraces") }
    }
}
```

**Change 5:** Observe showFloatingPanel changes to sync menu bar toggle:
```swift
// In applicationDidFinishLaunching, add:
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
```

- [ ] **Step 2: Build and verify**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/Mini_CapsuleApp.swift"
git commit -m "feat: wire menu bar service and new general/appearance settings tabs"
```

---

### Task 10: Final build, test, and verify

- [ ] **Step 1: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
# Expected: ** BUILD SUCCEEDED **
```

- [ ] **Step 2: Run tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test 2>&1 | tail -15
# Expected: ** TEST SUCCEEDED **
```

- [ ] **Step 3: Manual verification checklist**
1. Open settings → five tabs visible (通用, 外观, 剪贴板, 快捷键, 高级)
2. General: toggle menu bar off → warning appears → auto-re-enables
3. General: toggle floating panel off → capsule window hides → toggle back on → reappears
4. General: change collapsed style to dot → capsule becomes a 12×12 colored circle
5. General: change hover delays → verify expand/collapse timing
6. Appearance: adjust opacity slider → capsule changes opacity in real-time
7. Appearance: choose background image → expanded panel shows image behind material
8. Appearance: clear background → returns to normal
9. Menu bar: click 📋 icon → menu shows recent items, toggle, settings, quit
10. Menu bar: click a recent item → copies to clipboard
11. Dot: green for text, blue for image, orange for file, gray for empty
12. Custom dot color: pick a color → dot shows that color
