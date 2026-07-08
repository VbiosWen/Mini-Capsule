// Mini CapsuleTests/Settings/SettingsDataTests.swift
import Testing
import Foundation
@testable import Mini_Capsule

struct SettingsDataTests {
    @Test func defaultValuesAreCorrect() async throws {
        let data = SettingsData()

        // Clipboard
        #expect(data.historyMaxCount == 200)
        #expect(data.imageMaxSizeMB == 2)
        #expect(data.pollingInterval == 0.5)
        #expect(data.cleanupOnStartup == true)
        #expect(data.dedupEnabled == true)

        // Shortcuts
        #expect(data.showHideShortcut == "cmd+shift+V")
        #expect(data.quickPasteShortcut == "cmd+shift+C")
        #expect(data.togglePinShortcut == "")

        // Advanced
        #expect(data.iCloudSyncEnabled == false)

        // General
        #expect(data.launchAtLogin == false)
        #expect(data.showInMenuBar == true)
        #expect(data.showFloatingPanel == true)
        #expect(data.collapsedStyle == "capsule")
        #expect(data.hoverExpandDelay == 0.3)
        #expect(data.hoverCollapseDelay == 1.0)

        // Appearance
        #expect(data.panelOpacityUnfocused == 0.6)
        #expect(data.backgroundImageData == Data())
        #expect(data.ringDiameter == 30)
        #expect(data.capsuleWindowFrame == Data())
    }

    @Test func encodeDecodeRoundtripPreservesAllFields() throws {
        var original = SettingsData()
        original.historyMaxCount = 50
        original.pollingInterval = 1.0
        original.ringDiameter = 40
        original.showHideShortcut = "cmd+shift+X"

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SettingsData.self, from: jsonData)

        #expect(decoded.historyMaxCount == 50)
        #expect(decoded.pollingInterval == 1.0)
        #expect(decoded.ringDiameter == 40)
        #expect(decoded.showHideShortcut == "cmd+shift+X")

        // Unmodified fields should retain defaults
        #expect(decoded.imageMaxSizeMB == 2)
        #expect(decoded.cleanupOnStartup == true)
    }

    @Test func encodeDecodeRoundtripWithDataFields() throws {
        var original = SettingsData()
        let frameDict: [String: CGFloat] = ["x": 100, "y": 200, "w": 300, "h": 36]
        original.capsuleWindowFrame = (try? JSONEncoder().encode(frameDict)) ?? Data()
        original.backgroundImageData = Data([0x01, 0x02, 0x03])

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SettingsData.self, from: jsonData)

        #expect(decoded.capsuleWindowFrame == original.capsuleWindowFrame)
        #expect(decoded.backgroundImageData == original.backgroundImageData)
    }

    @Test func equatableConformance() async throws {
        let a = SettingsData()
        let b = SettingsData()
        #expect(a == b)

        var c = SettingsData()
        c.ringDiameter = 50
        #expect(a != c)
    }
}
