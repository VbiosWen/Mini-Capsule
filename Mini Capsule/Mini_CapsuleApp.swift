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

    private var capsuleWindowController: CapsuleWindowController?
    private var clipboardMonitor: ClipboardMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock and make the app a background accessory
        NSApp.setActivationPolicy(.accessory)

        // Close any auto-created SwiftUI windows
        DispatchQueue.main.async {
            for window in NSApp.windows {
                window.close()
            }
        }

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
        #else
        // iOS / visionOS: keep existing behavior
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        #endif
    }
}
