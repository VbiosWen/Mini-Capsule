// Mini Capsule/Services/MenuBarService.swift
import AppKit
import SwiftUI
import SwiftData

@MainActor
final class MenuBarService {
    private var statusItem: NSStatusItem?
    private var context: ModelContext?
    private var popover: NSPopover?
    private let settings: SettingsProtocol

    init(settings: SettingsProtocol) {
        self.settings = settings
    }

    func start(context: ModelContext) {
        self.context = context
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let icon = Self.menuBarIcon() {
            item.button?.image = icon
        } else {
            item.button?.title = "📋"
        }
        statusItem = item

        // Respect initial visibility setting
        statusItem?.isVisible = settings.showInMenuBar

        // Use target/action for left-click to toggle the popover
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(statusItemClicked)
        statusItem?.button?.sendAction(on: [.leftMouseDown])

        // Observe clipboard changes to allow refresh on next open
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Refresh happens naturally on next popover open via fresh fetch
        }
    }

    func stop() {
        popover?.close()
        popover = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    func updateVisibility(_ visible: Bool) {
        statusItem?.isVisible = visible
    }

    /// The app icon scaled for the status bar. Works on a copy so the shared
    /// `NSImage(named:)` cache keeps its original size.
    static func menuBarIcon() -> NSImage? {
        let source = NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage
        guard let icon = source?.copy() as? NSImage else { return nil }
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }

    // MARK: - Popover

    @objc private func statusItemClicked() {
        if let popover = popover, popover.isShown {
            popover.close()
            self.popover = nil
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button, let context = context else { return }

        // Fetch all items, newest first
        let descriptor = FetchDescriptor<ClipItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let items = (try? context.fetch(descriptor)) ?? []

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.animates = true

        let contentView = MenuBarPopoverView(
            items: items,
            showFloatingPanel: settings.showFloatingPanel,
            onSelect: { [weak self] item in
                self?.selectItem(item)
            },
            onToggleFloating: { [weak self] in
                self?.toggleFloatingPanel()
                self?.popover?.close()
                self?.popover = nil
            },
            onSettings: { [weak self] in
                self?.openSettings()
                self?.popover?.close()
                self?.popover = nil
            },
            onQuit: { [weak self] in
                self?.quitApp()
            }
        )

        let hostingController = NSHostingController(rootView: contentView)
        popover.contentViewController = hostingController
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        self.popover = popover
    }

    private func selectItem(_ item: ClipItem) {
        PasteService.copyToClipboard(item)
        item.pasteCount += 1
        item.lastPastedAt = Date()
        try? context?.save()
        popover?.close()
        popover = nil
    }

    // MARK: - Actions

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
        // Accessory apps aren't the active app when a status-bar popover is
        // clicked, so `showSettingsWindow:` would open the Settings window
        // behind everything (or not at all). Activate first — matches the
        // pattern in CapsuleWindowController before makeKey().
        NSApp.activate(ignoringOtherApps: true)
        // Send directly to NSApp instead of through the responder chain.
        // When the popover is open, the first responder is inside the
        // popover's content view, and the action may not reach NSApp.
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: NSApp, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: NSApp, from: nil)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
