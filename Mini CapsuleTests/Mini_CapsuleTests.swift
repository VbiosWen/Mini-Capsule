// Mini CapsuleTests/Mini_CapsuleTests.swift
import Testing
import Foundation
@testable import Mini_Capsule

@MainActor
struct SettingsStoreTests {

    @Test func defaults() async throws {
        // Reset UserDefaults for this suite
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "historyMaxCount")
        defaults.removeObject(forKey: "imageMaxSizeMB")
        defaults.removeObject(forKey: "pollingInterval")
        defaults.removeObject(forKey: "cleanupOnStartup")
        defaults.removeObject(forKey: "dedupEnabled")

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
    }
}
