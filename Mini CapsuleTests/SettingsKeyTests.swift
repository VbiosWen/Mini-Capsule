import Testing
@testable import Mini_Capsule

struct SettingsKeyTests {
    @Test func allKeysAreUnique() async throws {
        let allKeys = SettingsKey.allCases.map(\.rawValue)
        let uniqueKeys = Set(allKeys)
        #expect(allKeys.count == uniqueKeys.count, "All SettingsKey rawValues must be unique")
    }

    @Test func keyCountIsCorrect() async throws {
        #expect(SettingsKey.allCases.count == 19, "Expected 19 settings keys")
    }

    @Test func keysMatchExpectedValues() async throws {
        let expected: Set<String> = [
            "historyMaxCount", "imageMaxSizeMB", "pollingInterval",
            "cleanupOnStartup", "dedupEnabled",
            "showHideShortcut", "quickPasteShortcut", "togglePinShortcut",
            "iCloudSyncEnabled", "launchAtLogin", "showInMenuBar",
            "showFloatingPanel", "collapsedStyle", "hoverExpandDelay",
            "hoverCollapseDelay", "panelOpacityUnfocused",
            "backgroundImageData", "ringDiameter",
            "capsuleWindowFrame"
        ]
        let actual = Set(SettingsKey.allCases.map(\.rawValue))
        #expect(actual == expected, "SettingsKey cases must match expected key strings")
    }

    @Test func allCasesContainsCapsuleWindowFrame() async throws {
        let keys = SettingsKey.allCases.map(\.rawValue)
        #expect(keys.contains("capsuleWindowFrame"))
    }
}
