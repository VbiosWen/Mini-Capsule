// Mini Capsule/Mini_CapsuleApp.swift
import SwiftUI
import SwiftData

#if os(macOS)
@MainActor
class CapsuleAppDelegate: NSObject, NSApplicationDelegate {
    /// Shared model container, initialized once at startup.
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            ClipItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    let settingsStore = SettingsStore()

    private var capsuleWindowController: CapsuleWindowController?
    private var clipboardMonitor: ClipboardMonitor?
    private let hotKeyCenter = HotKeyCenter()
    private var menuBarService: MenuBarService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock and make the app a background accessory
        NSApp.setActivationPolicy(.accessory)

        // Load settings from JSON asynchronously, then finish setup
        Task { @MainActor in
            let persistence = SettingsPersistence()
            let loaded = await persistence.load()
            self.settingsStore.replaceData(with: loaded)
            // Ensure the file exists on disk (first launch creates it)
            try? await persistence.save(loaded)

            self.finishSetup()
        }
    }

    private func finishSetup() {
        // Startup safety: prevent "invisible app" — if both display modes are
        // off the user has no way to access this accessory app (no Dock icon).
        if !settingsStore.showInMenuBar && !settingsStore.showFloatingPanel {
            settingsStore.showInMenuBar = true
        }

        // Frequency cleanup on startup (only if enabled)
        if settingsStore.cleanupOnStartup {
            FrequencyCleanupService.performCleanup(
                context: Self.sharedModelContainer.mainContext,
                keepCount: nil,
                settings: settingsStore
            )
        }

        // Create capsule window — respect showFloatingPanel setting
        let controller = CapsuleWindowController(modelContainer: Self.sharedModelContainer, settingsStore: settingsStore)
        if settingsStore.showFloatingPanel {
            controller.showWindow()
        }
        capsuleWindowController = controller

        // Start clipboard monitoring
        let monitor = ClipboardMonitor(settings: settingsStore)
        monitor.start(context: Self.sharedModelContainer.mainContext)
        clipboardMonitor = monitor

        // Start menu bar — MenuBarService.start() respects showInMenuBar
        let menuBar = MenuBarService(settings: settingsStore)
        menuBar.start(context: Self.sharedModelContainer.mainContext)
        menuBarService = menuBar

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

        NotificationCenter.default.addObserver(
            forName: .showInMenuBarChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let show = notification.userInfo?["show"] as? Bool else { return }
            self?.menuBarService?.updateVisibility(show)
        }

        registerShortcuts()

        NotificationCenter.default.addObserver(
            forName: .shortcutsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.registerShortcuts()
        }
    }

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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When the user clicks the app icon while already running, toggle the
        // capsule expansion instead of showing the Settings window.
        if let controller = capsuleWindowController, controller.window?.isVisible == true {
            // Capsule is visible — post a notification so the view can expand
            NotificationCenter.default.post(
                name: .capsuleShouldToggleExpand,
                object: nil
            )
        } else {
            capsuleWindowController?.showWindow()
        }
        return false // Prevent default behavior (showing Settings window)
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stop()
        menuBarService?.stop()
    }
}
#endif

@main
struct Mini_CapsuleApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor var appDelegate: CapsuleAppDelegate
    #else
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            ClipItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    #endif

    var body: some Scene {
        #if os(macOS)
        // macOS: capsule window managed by CapsuleAppDelegate, no main window needed
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
        .environment(appDelegate.settingsStore)
        .modelContainer(CapsuleAppDelegate.sharedModelContainer)
        #else
        // iOS / visionOS: keep existing behavior
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        #endif
    }
}
