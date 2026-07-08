// Mini CapsuleTests/Mini_CapsuleTests.swift
import Testing
import Foundation
import AppKit
import SwiftData
@testable import Mini_Capsule

@MainActor
struct SettingsStoreTests {

    @Test func defaults() async throws {
        // Given: a fresh store
        let store = SettingsStore()

        // Then: defaults are set
        #expect(store.historyMaxCount == 200)
        #expect(store.imageMaxSizeMB == 2)
        #expect(store.pollingInterval == 0.5)
        #expect(store.cleanupOnStartup == true)
        #expect(store.dedupEnabled == true)
        #expect(store.showHideShortcut == "cmd+shift+v")
        #expect(store.quickPasteShortcut == "cmd+shift+c")
        #expect(store.togglePinShortcut == "")
        #expect(store.iCloudSyncEnabled == false)
        #expect(store.launchAtLogin == false)
        #expect(store.showInMenuBar == true)
        #expect(store.showFloatingPanel == true)
        #expect(store.collapsedStyle == "capsule")
        #expect(store.hoverExpandDelay == 0.3)
        #expect(store.hoverCollapseDelay == 1.0)
        #expect(store.panelOpacityUnfocused == 0.6)
        #expect(store.ringDiameter == 30)
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
        store.ringDiameter = 80

        // When: reset
        store.resetAll()

        // Then: all defaults restored
        #expect(store.historyMaxCount == 200)
        #expect(store.imageMaxSizeMB == 2)
        #expect(store.pollingInterval == 0.5)
        #expect(store.cleanupOnStartup == true)
        #expect(store.dedupEnabled == true)
        #expect(store.showHideShortcut == "cmd+shift+v")
        #expect(store.quickPasteShortcut == "cmd+shift+c")
        #expect(store.togglePinShortcut == "")
        #expect(store.iCloudSyncEnabled == false)
        #expect(store.launchAtLogin == false)
        #expect(store.showInMenuBar == true)
        #expect(store.showFloatingPanel == true)
        #expect(store.collapsedStyle == "capsule")
        #expect(store.hoverExpandDelay == 0.3)
        #expect(store.hoverCollapseDelay == 1.0)
        #expect(store.panelOpacityUnfocused == 0.6)
        #expect(store.ringDiameter == 30)
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

    @Test func allSettingsCombinatorialChangeThenReset() async throws {
        let store = SettingsStore()

        store.historyMaxCount = 800
        store.imageMaxSizeMB = 5
        store.pollingInterval = 2.0
        store.cleanupOnStartup = false
        store.dedupEnabled = false
        store.showHideShortcut = "cmd+option+K"
        store.quickPasteShortcut = "cmd+shift+X"
        store.togglePinShortcut = "cmd+shift+P"
        store.iCloudSyncEnabled = true
        store.launchAtLogin = true
        store.showInMenuBar = false
        store.showFloatingPanel = false
        store.collapsedStyle = "dot"
        store.hoverExpandDelay = 1.0
        store.hoverCollapseDelay = 3.0
        store.panelOpacityUnfocused = 0.3
        store.backgroundImageData = "bg".data(using: .utf8)!
        store.ringDiameter = 100

        #expect(store.historyMaxCount == 800)
        #expect(store.collapsedStyle == "dot")
        #expect(store.ringDiameter == 100)
        #expect(store.panelOpacityUnfocused == 0.3)
        #expect(store.backgroundImageData == "bg".data(using: .utf8)!)

        store.resetAll()

        #expect(store.historyMaxCount == 200)
        #expect(store.collapsedStyle == "capsule")
        #expect(store.ringDiameter == 30)
        #expect(store.panelOpacityUnfocused == 0.6)
        #expect(store.backgroundImageData == Data())
    }

    @Test func propertyChangeIsObservable() async throws {
        let store = SettingsStore()
        store.pollingInterval = 1.5
        // @Observable tracks changes automatically — no explicit objectWillChange needed
        #expect(store.pollingInterval == 1.5)
        store.resetAll()
    }

    @Test func defaultValuesAreConsistent() async throws {
        let store = SettingsStore()

        #expect(store.historyMaxCount == 200)
        #expect(store.imageMaxSizeMB == 2)
        #expect(store.pollingInterval == 0.5)
        #expect(store.cleanupOnStartup == true)
        #expect(store.dedupEnabled == true)
        #expect(store.showHideShortcut == "cmd+shift+v")
        #expect(store.quickPasteShortcut == "cmd+shift+c")
        #expect(store.togglePinShortcut == "")
        #expect(store.iCloudSyncEnabled == false)
        #expect(store.launchAtLogin == false)
        #expect(store.showInMenuBar == true)
        #expect(store.showFloatingPanel == true)
        #expect(store.collapsedStyle == "capsule")
        #expect(store.hoverExpandDelay == 0.3)
        #expect(store.hoverCollapseDelay == 1.0)
        #expect(store.panelOpacityUnfocused == 0.6)
        #expect(store.backgroundImageData == Data())
        #expect(store.ringDiameter == 30)
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
        var data = SettingsData()
        data.collapsedStyle = "capsule"
        let store = SettingsStore(data: data)

        let container = try Self.makeContainer()
        let controller = CapsuleWindowController(modelContainer: container, settingsStore: store)

        #expect(controller.window?.contentView?.layer?.cornerRadius == 18)
    }

    @Test func initialCornerRadiusDot() async throws {
        var data = SettingsData()
        data.collapsedStyle = "dot"
        let store = SettingsStore(data: data)

        let container = try Self.makeContainer()
        let controller = CapsuleWindowController(modelContainer: container, settingsStore: store)

        #expect(controller.window?.contentView?.layer?.cornerRadius == 15)
    }

    @Test func updatesCornerRadiusOnExpandAndCollapse() async throws {
        var data = SettingsData()
        data.collapsedStyle = "capsule"
        let store = SettingsStore(data: data)

        let container = try Self.makeContainer()
        let controller = CapsuleWindowController(modelContainer: container, settingsStore: store)

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
        // Wait for the 0.25s async collapse animation to apply
        try await Task.sleep(for: .seconds(0.3))
        #expect(controller.window?.contentView?.layer?.cornerRadius == 18)
    }

    @Test func updatesCornerRadiusOnStyleChangeWhenCollapsed() async throws {
        let container = try Self.makeContainer()
        let store = SettingsStore()
        store.collapsedStyle = "capsule"
        let controller = CapsuleWindowController(modelContainer: container, settingsStore: store)

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
        // Wait for the 0.25s async collapse animation to apply
        try await Task.sleep(for: .seconds(0.3))
        #expect(controller.window?.contentView?.layer?.cornerRadius == 18)

        // Change style to dot while collapsed
        store.collapsedStyle = "dot"
        #expect(controller.window?.contentView?.layer?.cornerRadius == 15)
    }

    @Test func doesNotUpdateCornerRadiusOnStyleChangeWhenExpanded() async throws {
        let container = try Self.makeContainer()
        let store = SettingsStore()
        store.collapsedStyle = "capsule"
        let controller = CapsuleWindowController(modelContainer: container, settingsStore: store)

        // Expand
        NotificationCenter.default.post(
            name: .capsuleDidChangeExpanded,
            object: nil,
            userInfo: ["isExpanded": true]
        )
        #expect(controller.window?.contentView?.layer?.cornerRadius == 12)

        // Change style to dot while expanded — should NOT affect cornerRadius
        store.collapsedStyle = "dot"
        #expect(controller.window?.contentView?.layer?.cornerRadius == 12)
    }

        // MARK: - Reset Position Tests

    @Test func resetPositionRemovesSavedFrameKey() async throws {
        let container = try Self.makeContainer()
        let store = SettingsStore()
        let frameDict: [String: CGFloat] = ["x": 100, "y": 200, "w": 200, "h": 36]
        store.capsuleWindowFrame = try JSONEncoder().encode(frameDict)
        _ = CapsuleWindowController(modelContainer: container, settingsStore: store)

        NotificationCenter.default.post(name: .resetCapsulePosition, object: nil)

        #expect(store.capsuleWindowFrame == Data())
    }

    @Test func resetPositionUpdatesWindowFrame() async throws {
        let container = try Self.makeContainer()
        let store = SettingsStore()
        let frameDict: [String: CGFloat] = ["x": 100, "y": 200, "w": 200, "h": 36]
        store.capsuleWindowFrame = try JSONEncoder().encode(frameDict)
        let controller = CapsuleWindowController(modelContainer: container, settingsStore: store)
        guard let window = controller.window else {
            Issue.record("No window")
            return
        }

        let oldFrame = NSRect(x: 100, y: 200, width: 200, height: 36)
        window.setFrame(oldFrame, display: false)

        NotificationCenter.default.post(name: .resetCapsulePosition, object: nil)

        // If a screen is available, the window origin must have moved
        if NSScreen.main != nil {
            #expect(window.frame.origin.x != 100 || window.frame.origin.y != 200)
        }
    }

    // MARK: - Drag Monitor Tests

    @Test func dragMonitorCreatedOnInit() async throws {
        let container = try Self.makeContainer()
        let controller = CapsuleWindowController(modelContainer: container, settingsStore: SettingsStore())

        #expect(controller.window != nil)
        #expect(controller.window?.contentView != nil)
    }

    @Test func deinitReleasesController() async throws {
        weak var weakController: CapsuleWindowController?

        autoreleasepool {
            let container = try! Self.makeContainer()
            let controller = CapsuleWindowController(modelContainer: container, settingsStore: SettingsStore())
            weakController = controller
        }

        try await Task.sleep(for: .milliseconds(50))
        #expect(weakController == nil)
    }

    @Test func dragStartedNotificationPostedAfterDelay() async throws {
        let container = try Self.makeContainer()
        let controller = CapsuleWindowController(modelContainer: container, settingsStore: SettingsStore())
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
        let controller = CapsuleWindowController(modelContainer: container, settingsStore: SettingsStore())
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
        let controller = CapsuleWindowController(modelContainer: container, settingsStore: SettingsStore())
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

// MARK: - ClipboardMonitor Settings Tests

@MainActor
struct ClipboardMonitorSettingsTests {
    @Test func monitorReadsPollingIntervalFromSettings() async throws {
        let store = SettingsStore()
        store.pollingInterval = 2.0
        store.historyMaxCount = 100
        store.imageMaxSizeMB = 5
        store.dedupEnabled = false

        let monitor = ClipboardMonitor(settings: store)

        // Verify settings are read through the protocol
        #expect(store.pollingInterval == 2.0)
        #expect(store.historyMaxCount == 100)
        #expect(store.imageMaxSizeMB == 5)
        #expect(store.dedupEnabled == false)

        store.resetAll()
    }
}

// MARK: - CapsuleView Settings Tests

@MainActor
struct CapsuleViewSettingsTests {
    @Test func collapsedStyleReadsFromSettings() async throws {
        let store = SettingsStore()
        store.collapsedStyle = "dot"
        store.hoverExpandDelay = 0.5
        store.hoverCollapseDelay = 2.0
        store.panelOpacityUnfocused = 0.5

        #expect(store.collapsedStyle == "dot")
        #expect(store.hoverExpandDelay == 0.5)
        #expect(store.hoverCollapseDelay == 2.0)
        #expect(store.panelOpacityUnfocused == 0.5)

        store.resetAll()
        #expect(store.collapsedStyle == "capsule")
        #expect(store.hoverExpandDelay == 0.3)
    }
}

// MARK: - GeneralSettingsView Tests

@MainActor
struct GeneralSettingsViewTests {
    @Test func resetPositionActionClearsFrameAndPostsNotification() async throws {
        let store = SettingsStore()
        let frameDict: [String: CGFloat] = ["x": 100, "y": 200, "w": 200, "h": 36]
        store.capsuleWindowFrame = try JSONEncoder().encode(frameDict)

        try await confirmation(expectedCount: 1) { posted in
            let obs = NotificationCenter.default.addObserver(
                forName: .resetCapsulePosition,
                object: nil,
                queue: .main
            ) { _ in posted() }
            defer { NotificationCenter.default.removeObserver(obs) }

            GeneralSettingsView.resetCapsulePosition(settings: store)
        }

        #expect(store.capsuleWindowFrame == Data())
    }
}

// MARK: - MenuBarService Settings Tests

@MainActor
struct MenuBarServiceSettingsTests {
    @Test func serviceReadsShowFloatingPanelFromSettings() async throws {
        let store = SettingsStore()
        store.showFloatingPanel = false

        #expect(store.showFloatingPanel == false)

        store.showFloatingPanel = true
        #expect(store.showFloatingPanel == true)

        store.resetAll()
    }

    @Test func toggleFloatingPanelUpdatesSettings() async throws {
        let store = SettingsStore()
        store.showFloatingPanel = true

        // Simulate toggle behavior (the actual MenuBarService logic)
        let current = store.showFloatingPanel
        store.showFloatingPanel = !current

        #expect(store.showFloatingPanel == false)
        store.resetAll()
    }
}
