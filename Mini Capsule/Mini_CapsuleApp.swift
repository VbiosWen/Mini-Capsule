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
    private var shortcutMonitor: Any?
    private var menuBarService: MenuBarService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock and make the app a background accessory
        NSApp.setActivationPolicy(.accessory)

        // Frequency cleanup on startup
        FrequencyCleanupService.performCleanup(
            context: Self.sharedModelContainer.mainContext,
            keepCount: 50
        )

        // Create capsule window
        let controller = CapsuleWindowController(modelContainer: Self.sharedModelContainer, settingsStore: settingsStore)
        controller.showWindow()
        capsuleWindowController = controller

        // Start clipboard monitoring
        let monitor = ClipboardMonitor(settings: settingsStore)
        monitor.start(context: Self.sharedModelContainer.mainContext)
        clipboardMonitor = monitor

        // Start menu bar
        let menuBar = MenuBarService()
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

        registerShortcuts()
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
        .environmentObject(appDelegate.settingsStore)
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
