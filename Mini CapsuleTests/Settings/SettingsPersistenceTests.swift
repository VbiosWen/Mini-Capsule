// Mini CapsuleTests/Settings/SettingsPersistenceTests.swift
import Testing
import Foundation
@testable import Mini_Capsule

struct SettingsPersistenceTests {
    @Test func loadReturnsDefaultsWhenFileMissing() async throws {
        // Clean up any existing test file first.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let testFile = home.appendingPathComponent(".minicapule/settings.json")
        try? FileManager.default.removeItem(at: testFile)

        let persistence = SettingsPersistence()
        let data = await persistence.load()
        #expect(data == SettingsData())
    }

    @Test func saveAndLoadRoundtrip() async throws {
        // Clean up before test
        let home = FileManager.default.homeDirectoryForCurrentUser
        let testFile = home.appendingPathComponent(".minicapule/settings.json")
        try? FileManager.default.removeItem(at: testFile)

        let persistence = SettingsPersistence()

        var original = SettingsData()
        original.historyMaxCount = 99
        original.ringDiameter = 45

        try await persistence.save(original)
        let loaded = await persistence.load()

        #expect(loaded.historyMaxCount == 99)
        #expect(loaded.ringDiameter == 45)

        // Clean up test file
        try? FileManager.default.removeItem(at: testFile)
    }

    @Test func loadReturnsDefaultsWhenJSONCorrupted() async throws {
        // Write invalid JSON directly to the file
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".minicapule")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("settings.json")
        try "{invalid json}".write(to: file, atomically: true, encoding: .utf8)

        let persistence = SettingsPersistence()
        let data = await persistence.load()

        #expect(data == SettingsData())

        // Clean up
        try? FileManager.default.removeItem(at: file)
    }
}
