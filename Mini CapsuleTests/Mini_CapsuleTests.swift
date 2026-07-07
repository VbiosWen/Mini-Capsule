// Mini CapsuleTests/Mini_CapsuleTests.swift
import Testing
import Foundation
import AppKit
import SwiftData
@testable import Mini_Capsule

@MainActor
struct SettingsStoreTests {

    private static let allKeys = [
        "historyMaxCount", "imageMaxSizeMB", "pollingInterval", "cleanupOnStartup", "dedupEnabled",
        "showHideShortcut", "quickPasteShortcut", "togglePinShortcut", "iCloudSyncEnabled",
        "launchAtLogin", "showInMenuBar", "showFloatingPanel", "collapsedStyle",
        "hoverExpandDelay", "hoverCollapseDelay",
        "panelOpacityUnfocused", "backgroundImageData", "dotColorMode", "dotCustomColor"
    ]

    @Test func defaults() async throws {
        // Reset all UserDefaults keys for clean state
        let defaults = UserDefaults.standard
        for key in Self.allKeys {
            defaults.removeObject(forKey: key)
        }

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
        #expect(store.launchAtLogin == false)
        #expect(store.showInMenuBar == true)
        #expect(store.showFloatingPanel == true)
        #expect(store.collapsedStyle == "capsule")
        #expect(store.hoverExpandDelay == 0.3)
        #expect(store.hoverCollapseDelay == 1.0)
        #expect(store.panelOpacityUnfocused == 0.6)
        #expect(store.dotColorMode == "auto")
        #expect(store.dotCustomColor == "#007AFF")
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
        store.launchAtLogin = true
        store.showInMenuBar = false
        store.showFloatingPanel = false
        store.collapsedStyle = "dot"
        store.hoverExpandDelay = 1.0
        store.hoverCollapseDelay = 3.0
        store.panelOpacityUnfocused = 0.3
        store.dotColorMode = "custom"
        store.dotCustomColor = "#FF0000"

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
        #expect(store.launchAtLogin == false)
        #expect(store.showInMenuBar == true)
        #expect(store.showFloatingPanel == true)
        #expect(store.collapsedStyle == "capsule")
        #expect(store.hoverExpandDelay == 0.3)
        #expect(store.hoverCollapseDelay == 1.0)
        #expect(store.panelOpacityUnfocused == 0.6)
        #expect(store.dotColorMode == "auto")
        #expect(store.dotCustomColor == "#007AFF")
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

        // Cleanup
        store.resetAll()
    }

    // MARK: - Notification Names

    @Test func notificationNameCapsuleDragStarted() async throws {
        #expect(NSNotification.Name.capsuleDragStarted == NSNotification.Name("capsuleDragStarted"))
    }

    @Test func notificationNameCapsuleDragEnded() async throws {
        #expect(NSNotification.Name.capsuleDragEnded == NSNotification.Name("capsuleDragEnded"))
    }

    @Test func notificationNameResetCapsulePosition() async throws {
        #expect(NSNotification.Name.resetCapsulePosition == NSNotification.Name("resetCapsulePosition"))
    }
}

// MARK: - CapsuleWindowController Tests

@MainActor
struct CapsuleWindowControllerTests {
    /// Create an in-memory ModelContainer for testing.
    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test func initialCornerRadiusCapsule() async throws {
        let defaults = UserDefaults.standard
        defaults.set("capsule", forKey: "collapsedStyle")

        let container = try Self.makeContainer()
        let controller = CapsuleWindowController(modelContainer: container)

        #expect(controller.window?.contentView?.layer?.cornerRadius == 18)
    }

    @Test func initialCornerRadiusDot() async throws {
        let defaults = UserDefaults.standard
        defaults.set("dot", forKey: "collapsedStyle")

        let container = try Self.makeContainer()
        let controller = CapsuleWindowController(modelContainer: container)

        #expect(controller.window?.contentView?.layer?.cornerRadius == 6)
    }

    @Test func updatesCornerRadiusOnExpandAndCollapse() async throws {
        let defaults = UserDefaults.standard
        defaults.set("capsule", forKey: "collapsedStyle")

        let container = try Self.makeContainer()
        let controller = CapsuleWindowController(modelContainer: container)

        // Initial: capsule style → cornerRadius 18
        #expect(controller.window?.contentView?.layer?.cornerRadius == 18)

        // Expand → 12
        NotificationCenter.default.post(
            name: .capsuleDidChangeExpanded,
            object: nil,
            userInfo: ["isExpanded": true]
        )
        #expect(controller.window?.contentView?.layer?.cornerRadius == 12)

        // Collapse back to capsule → 18
        NotificationCenter.default.post(
            name: .capsuleDidChangeExpanded,
            object: nil,
            userInfo: ["isExpanded": false]
        )
        #expect(controller.window?.contentView?.layer?.cornerRadius == 18)
    }

    @Test func updatesCornerRadiusOnStyleChangeWhenCollapsed() async throws {
        let defaults = UserDefaults.standard
        defaults.set("capsule", forKey: "collapsedStyle")

        let container = try Self.makeContainer()
        let controller = CapsuleWindowController(modelContainer: container)

        // Start collapsed as capsule → 18
        #expect(controller.window?.contentView?.layer?.cornerRadius == 18)

        // Expand then collapse
        NotificationCenter.default.post(
            name: .capsuleDidChangeExpanded,
            object: nil,
            userInfo: ["isExpanded": true]
        )
        #expect(controller.window?.contentView?.layer?.cornerRadius == 12)

        NotificationCenter.default.post(
            name: .capsuleDidChangeExpanded,
            object: nil,
            userInfo: ["isExpanded": false]
        )
        #expect(controller.window?.contentView?.layer?.cornerRadius == 18)

        // Change style to dot while collapsed
        defaults.set("dot", forKey: "collapsedStyle")
        NotificationCenter.default.post(
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        #expect(controller.window?.contentView?.layer?.cornerRadius == 6)
    }

    @Test func doesNotUpdateCornerRadiusOnStyleChangeWhenExpanded() async throws {
        let defaults = UserDefaults.standard
        defaults.set("capsule", forKey: "collapsedStyle")

        let container = try Self.makeContainer()
        let controller = CapsuleWindowController(modelContainer: container)

        // Expand
        NotificationCenter.default.post(
            name: .capsuleDidChangeExpanded,
            object: nil,
            userInfo: ["isExpanded": true]
        )
        #expect(controller.window?.contentView?.layer?.cornerRadius == 12)

        // Change style to dot while expanded — should NOT affect cornerRadius
        defaults.set("dot", forKey: "collapsedStyle")
        NotificationCenter.default.post(
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        #expect(controller.window?.contentView?.layer?.cornerRadius == 12)
    }

    // MARK: - Drag Monitor Tests

    @Test func dragMonitorCreatedOnInit() async throws {
        let container = try Self.makeContainer()
        let controller = CapsuleWindowController(modelContainer: container)

        #expect(controller.window != nil)
        #expect(controller.window?.contentView != nil)
    }

    @Test func deinitReleasesController() async throws {
        weak var weakController: CapsuleWindowController?

        autoreleasepool {
            let container = try! Self.makeContainer()
            let controller = CapsuleWindowController(modelContainer: container)
            weakController = controller
        }

        try await Task.sleep(for: .milliseconds(50))
        #expect(weakController == nil)
    }

    @Test func dragStartedNotificationPostedAfterDelay() async throws {
        let container = try Self.makeContainer()
        let controller = CapsuleWindowController(modelContainer: container)
        guard let window = controller.window else {
            Issue.record("No window")
            return
        }

        let mouseDown = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))

        try await confirmation(expectedCount: 1) { started in
            let obs = NotificationCenter.default.addObserver(
                forName: .capsuleDragStarted,
                object: nil,
                queue: .main
            ) { _ in started() }
            defer { NotificationCenter.default.removeObserver(obs) }

            NSApp.sendEvent(mouseDown)
            try await Task.sleep(for: .seconds(0.6))
        }
    }

    @Test func dragEndedNotificationPostedOnMouseUp() async throws {
        let container = try Self.makeContainer()
        let controller = CapsuleWindowController(modelContainer: container)
        guard let window = controller.window else {
            Issue.record("No window")
            return
        }

        let mouseDown = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 0
        ))
        let mouseUp = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 0
        ))

        try await confirmation(expectedCount: 1) { ended in
            let obs = NotificationCenter.default.addObserver(
                forName: .capsuleDragEnded,
                object: nil,
                queue: .main
            ) { _ in ended() }
            defer { NotificationCenter.default.removeObserver(obs) }

            NSApp.sendEvent(mouseDown)
            try await Task.sleep(for: .milliseconds(50))
            NSApp.sendEvent(mouseUp)
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    @Test func dragStartedNotPostedWhenMouseUpBeforePrimer() async throws {
        let container = try Self.makeContainer()
        let controller = CapsuleWindowController(modelContainer: container)
        guard let window = controller.window else {
            Issue.record("No window")
            return
        }

        let mouseDown = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 0
        ))
        let mouseUp = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 0
        ))

        try await confirmation(expectedCount: 0) { started in
            let obs = NotificationCenter.default.addObserver(
                forName: .capsuleDragStarted,
                object: nil,
                queue: .main
            ) { _ in started() }
            defer { NotificationCenter.default.removeObserver(obs) }

            NSApp.sendEvent(mouseDown)
            NSApp.sendEvent(mouseUp)
            try await Task.sleep(for: .seconds(0.6))
        }
    }
}
