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

// Tolerant decoding: missing keys fall back to defaults so that adding a
// new setting in a future version does not wipe a user's existing file.
// Placed in an extension so the synthesized SettingsData() init survives.
extension SettingsData {
    private enum CodingKeys: String, CodingKey {
        case historyMaxCount, imageMaxSizeMB, pollingInterval, cleanupOnStartup, dedupEnabled
        case showHideShortcut, quickPasteShortcut, togglePinShortcut
        case iCloudSyncEnabled
        case launchAtLogin, showInMenuBar, showFloatingPanel, collapsedStyle, hoverExpandDelay, hoverCollapseDelay
        case panelOpacityUnfocused, backgroundImageData, ringDiameter, capsuleWindowFrame
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SettingsData()
        historyMaxCount     = try c.decodeIfPresent(Int.self,    forKey: .historyMaxCount)     ?? d.historyMaxCount
        imageMaxSizeMB      = try c.decodeIfPresent(Int.self,    forKey: .imageMaxSizeMB)      ?? d.imageMaxSizeMB
        pollingInterval     = try c.decodeIfPresent(Double.self, forKey: .pollingInterval)     ?? d.pollingInterval
        cleanupOnStartup    = try c.decodeIfPresent(Bool.self,   forKey: .cleanupOnStartup)    ?? d.cleanupOnStartup
        dedupEnabled        = try c.decodeIfPresent(Bool.self,   forKey: .dedupEnabled)        ?? d.dedupEnabled
        showHideShortcut    = try c.decodeIfPresent(String.self, forKey: .showHideShortcut)    ?? d.showHideShortcut
        quickPasteShortcut  = try c.decodeIfPresent(String.self, forKey: .quickPasteShortcut)  ?? d.quickPasteShortcut
        togglePinShortcut   = try c.decodeIfPresent(String.self, forKey: .togglePinShortcut)   ?? d.togglePinShortcut
        iCloudSyncEnabled   = try c.decodeIfPresent(Bool.self,   forKey: .iCloudSyncEnabled)   ?? d.iCloudSyncEnabled
        launchAtLogin       = try c.decodeIfPresent(Bool.self,   forKey: .launchAtLogin)       ?? d.launchAtLogin
        showInMenuBar       = try c.decodeIfPresent(Bool.self,   forKey: .showInMenuBar)       ?? d.showInMenuBar
        showFloatingPanel   = try c.decodeIfPresent(Bool.self,   forKey: .showFloatingPanel)   ?? d.showFloatingPanel
        collapsedStyle      = try c.decodeIfPresent(String.self, forKey: .collapsedStyle)      ?? d.collapsedStyle
        hoverExpandDelay    = try c.decodeIfPresent(Double.self, forKey: .hoverExpandDelay)    ?? d.hoverExpandDelay
        hoverCollapseDelay  = try c.decodeIfPresent(Double.self, forKey: .hoverCollapseDelay)  ?? d.hoverCollapseDelay
        panelOpacityUnfocused = try c.decodeIfPresent(Double.self, forKey: .panelOpacityUnfocused) ?? d.panelOpacityUnfocused
        backgroundImageData = try c.decodeIfPresent(Data.self,   forKey: .backgroundImageData) ?? d.backgroundImageData
        ringDiameter        = try c.decodeIfPresent(Double.self, forKey: .ringDiameter)        ?? d.ringDiameter
        capsuleWindowFrame  = try c.decodeIfPresent(Data.self,   forKey: .capsuleWindowFrame)  ?? d.capsuleWindowFrame
    }
}
