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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock and make the app a background accessory
        NSApp.setActivationPolicy(.accessory)

        // Frequency cleanup on startup
        FrequencyCleanupService.performCleanup(
            context: Self.sharedModelContainer.mainContext,
            keepCount: 50
        )

        // Create capsule window
        let controller = CapsuleWindowController(modelContainer: Self.sharedModelContainer)
        controller.showWindow()
        capsuleWindowController = controller

        // Start clipboard monitoring
        let monitor = ClipboardMonitor()
        monitor.start(context: Self.sharedModelContainer.mainContext)
        clipboardMonitor = monitor
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stop()
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
        // macOS: hide main window, capsule window managed by CapsuleAppDelegate
        WindowGroup {
            EmptyView()
                .hidden()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

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
        #else
        // iOS / visionOS: keep existing behavior
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        #endif
    }
}
