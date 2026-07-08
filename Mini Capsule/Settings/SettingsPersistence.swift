// Mini Capsule/Settings/SettingsPersistence.swift
import Foundation

/// Actor that handles reading/writing SettingsData to a JSON file at ~/.minicapule/settings.json.
/// File isolation is achieved through actor serialization.
actor SettingsPersistence {
    private let fileURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".minicapule")
        self.fileURL = dir.appendingPathComponent("settings.json")
    }

    /// Load settings from disk. Returns default SettingsData if the file is missing or corrupted.
    func load() -> SettingsData {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(SettingsData.self, from: data)
        else {
            return SettingsData()
        }
        return settings
    }

    /// Persist settings to disk. Creates the .minicapule directory if it doesn't exist.
    /// Uses atomic write to prevent file corruption on crash.
    func save(_ data: SettingsData) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: fileURL, options: .atomic)
    }
}
