// Mini CapsuleTests/Mini_CapsuleTests.swift
import Testing
import Foundation
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
