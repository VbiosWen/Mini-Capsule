// Mini Capsule/Settings/SettingsKey.swift

/// UserDefaults key constants for all settings.
/// Private to the Settings module — only `SettingsStore` uses these directly.
enum SettingsKey: String, CaseIterable {
    // Clipboard
    case historyMaxCount
    case imageMaxSizeMB
    case pollingInterval
    case cleanupOnStartup
    case dedupEnabled

    // Shortcuts
    case showHideShortcut
    case quickPasteShortcut
    case togglePinShortcut

    // Advanced
    case iCloudSyncEnabled

    // General
    case launchAtLogin
    case showInMenuBar
    case showFloatingPanel
    case collapsedStyle
    case hoverExpandDelay
    case hoverCollapseDelay

    // Appearance
    case panelOpacityUnfocused
    case backgroundImageData
    case dotColorMode
    case dotCustomColor

    /// Window frame position persistence key (JSON-encoded [String: CGFloat]).
    case capsuleWindowFrame
}
