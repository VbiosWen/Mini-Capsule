// Mini Capsule/Settings/SettingsData.swift
import Foundation

/// All user-configurable settings as a single Codable struct.
/// Default values are defined inline — `SettingsData()` represents the default configuration.
struct SettingsData: Codable, Equatable {
    // MARK: - Clipboard
    var historyMaxCount: Int = 200
    var imageMaxSizeMB: Int = 2
    var pollingInterval: Double = 0.5
    var cleanupOnStartup: Bool = true
    var dedupEnabled: Bool = true

    // MARK: - Shortcuts
    var showHideShortcut: String = "cmd+shift+V"
    var quickPasteShortcut: String = "cmd+shift+C"
    var togglePinShortcut: String = ""

    // MARK: - Advanced
    var iCloudSyncEnabled: Bool = false

    // MARK: - General
    var launchAtLogin: Bool = false
    var showInMenuBar: Bool = true
    var showFloatingPanel: Bool = true
    var collapsedStyle: String = "capsule"
    var hoverExpandDelay: Double = 0.3
    var hoverCollapseDelay: Double = 1.0

    // MARK: - Appearance
    var panelOpacityUnfocused: Double = 0.6
    var backgroundImageData: Data = Data()
    var ringDiameter: Double = 30
    var capsuleWindowFrame: Data = Data()
}
