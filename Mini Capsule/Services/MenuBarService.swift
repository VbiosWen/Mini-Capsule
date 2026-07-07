// Mini Capsule/Services/MenuBarService.swift
import AppKit
import SwiftUI
import SwiftData

@MainActor
final class MenuBarService: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var context: ModelContext?
    private var menu: NSMenu?
    private var mouseMonitor: Any?
    private let settings: SettingsProtocol

    init(settings: SettingsProtocol) {
        self.settings = settings
    }

    func start(context: ModelContext) {
        self.context = context
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "📋"
        statusItem = item

        rebuildMenu()
        statusItem?.button?.action = nil
        statusItem?.button?.sendAction(on: [.leftMouseDown])

        // Use mouseDown to show menu
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
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
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
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

        let showFloating = settings.showFloatingPanel

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
        let current = settings.showFloatingPanel
        settings.showFloatingPanel = !current
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
