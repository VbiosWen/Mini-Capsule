// Mini Capsule/Settings/SettingsProtocol.swift
import SwiftData
import Foundation

/// Protocol for all settings access. Enables dependency injection and test mocking.
protocol SettingsProtocol: AnyObject {
    // MARK: - Clipboard
    var historyMaxCount: Int { get set }
    var imageMaxSizeMB: Int { get set }
    var pollingInterval: Double { get set }
    var cleanupOnStartup: Bool { get set }
    var dedupEnabled: Bool { get set }

    // MARK: - Shortcuts
    var showHideShortcut: String { get set }
    var quickPasteShortcut: String { get set }
    var togglePinShortcut: String { get set }

    // MARK: - Advanced
    var iCloudSyncEnabled: Bool { get set }

    // MARK: - General
    var launchAtLogin: Bool { get set }
    var showInMenuBar: Bool { get set }
    var showFloatingPanel: Bool { get set }
    var collapsedStyle: String { get set }
    var hoverExpandDelay: Double { get set }
    var hoverCollapseDelay: Double { get set }

    // MARK: - Appearance
    var panelOpacityUnfocused: Double { get set }
    var backgroundImageData: Data { get set }
    var dotColorMode: String { get set }
    var dotCustomColor: String { get set }

    // MARK: - Actions
    func resetAll()
    func exportData(context: ModelContext) -> Data?
    func importData(_ data: Data, context: ModelContext) throws
    func clearAllHistory(context: ModelContext)
}
