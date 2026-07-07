// Mini Capsule/Settings/SettingsStore.swift
import SwiftUI
import SwiftData
import Foundation
import Observation

/// Export/import DTO for ClipItem serialization.
private struct ClipItemExport: Codable {
    let type: String
    let content: String?
    let fileName: String?
    let timestamp: Date
    let pasteCount: Int
    let sourceApp: String?
}

@MainActor
@Observable
final class SettingsStore: SettingsProtocol {
    // MARK: - Clipboard

    var historyMaxCount: Int {
        get {
            access(keyPath: \.historyMaxCount)
            return UserDefaults.standard.object(forKey: SettingsKey.historyMaxCount.rawValue) as? Int ?? 200
        }
        set {
            withMutation(keyPath: \.historyMaxCount) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.historyMaxCount.rawValue)
            }
        }
    }

    var imageMaxSizeMB: Int {
        get {
            access(keyPath: \.imageMaxSizeMB)
            return UserDefaults.standard.object(forKey: SettingsKey.imageMaxSizeMB.rawValue) as? Int ?? 2
        }
        set {
            withMutation(keyPath: \.imageMaxSizeMB) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.imageMaxSizeMB.rawValue)
            }
        }
    }

    var pollingInterval: Double {
        get {
            access(keyPath: \.pollingInterval)
            return UserDefaults.standard.object(forKey: SettingsKey.pollingInterval.rawValue) as? Double ?? 0.5
        }
        set {
            withMutation(keyPath: \.pollingInterval) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.pollingInterval.rawValue)
            }
        }
    }

    var cleanupOnStartup: Bool {
        get {
            access(keyPath: \.cleanupOnStartup)
            return UserDefaults.standard.object(forKey: SettingsKey.cleanupOnStartup.rawValue) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.cleanupOnStartup) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.cleanupOnStartup.rawValue)
            }
        }
    }

    var dedupEnabled: Bool {
        get {
            access(keyPath: \.dedupEnabled)
            return UserDefaults.standard.object(forKey: SettingsKey.dedupEnabled.rawValue) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.dedupEnabled) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.dedupEnabled.rawValue)
            }
        }
    }

    // MARK: - Shortcuts

    var showHideShortcut: String {
        get {
            access(keyPath: \.showHideShortcut)
            return UserDefaults.standard.string(forKey: SettingsKey.showHideShortcut.rawValue) ?? "cmd+shift+V"
        }
        set {
            withMutation(keyPath: \.showHideShortcut) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.showHideShortcut.rawValue)
            }
        }
    }

    var quickPasteShortcut: String {
        get {
            access(keyPath: \.quickPasteShortcut)
            return UserDefaults.standard.string(forKey: SettingsKey.quickPasteShortcut.rawValue) ?? "cmd+shift+C"
        }
        set {
            withMutation(keyPath: \.quickPasteShortcut) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.quickPasteShortcut.rawValue)
            }
        }
    }

    var togglePinShortcut: String {
        get {
            access(keyPath: \.togglePinShortcut)
            return UserDefaults.standard.string(forKey: SettingsKey.togglePinShortcut.rawValue) ?? ""
        }
        set {
            withMutation(keyPath: \.togglePinShortcut) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.togglePinShortcut.rawValue)
            }
        }
    }

    // MARK: - Advanced

    var iCloudSyncEnabled: Bool {
        get {
            access(keyPath: \.iCloudSyncEnabled)
            return UserDefaults.standard.object(forKey: SettingsKey.iCloudSyncEnabled.rawValue) as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.iCloudSyncEnabled) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.iCloudSyncEnabled.rawValue)
            }
        }
    }

    // MARK: - General

    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return UserDefaults.standard.object(forKey: SettingsKey.launchAtLogin.rawValue) as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.launchAtLogin) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.launchAtLogin.rawValue)
            }
        }
    }

    var showInMenuBar: Bool {
        get {
            access(keyPath: \.showInMenuBar)
            return UserDefaults.standard.object(forKey: SettingsKey.showInMenuBar.rawValue) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.showInMenuBar) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.showInMenuBar.rawValue)
            }
        }
    }

    var showFloatingPanel: Bool {
        get {
            access(keyPath: \.showFloatingPanel)
            return UserDefaults.standard.object(forKey: SettingsKey.showFloatingPanel.rawValue) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.showFloatingPanel) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.showFloatingPanel.rawValue)
            }
        }
    }

    var collapsedStyle: String {
        get {
            access(keyPath: \.collapsedStyle)
            return UserDefaults.standard.string(forKey: SettingsKey.collapsedStyle.rawValue) ?? "capsule"
        }
        set {
            withMutation(keyPath: \.collapsedStyle) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.collapsedStyle.rawValue)
            }
        }
    }

    var hoverExpandDelay: Double {
        get {
            access(keyPath: \.hoverExpandDelay)
            return UserDefaults.standard.object(forKey: SettingsKey.hoverExpandDelay.rawValue) as? Double ?? 0.3
        }
        set {
            withMutation(keyPath: \.hoverExpandDelay) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.hoverExpandDelay.rawValue)
            }
        }
    }

    var hoverCollapseDelay: Double {
        get {
            access(keyPath: \.hoverCollapseDelay)
            return UserDefaults.standard.object(forKey: SettingsKey.hoverCollapseDelay.rawValue) as? Double ?? 1.0
        }
        set {
            withMutation(keyPath: \.hoverCollapseDelay) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.hoverCollapseDelay.rawValue)
            }
        }
    }

    // MARK: - Appearance

    var panelOpacityUnfocused: Double {
        get {
            access(keyPath: \.panelOpacityUnfocused)
            return UserDefaults.standard.object(forKey: SettingsKey.panelOpacityUnfocused.rawValue) as? Double ?? 0.6
        }
        set {
            withMutation(keyPath: \.panelOpacityUnfocused) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.panelOpacityUnfocused.rawValue)
            }
        }
    }

    var backgroundImageData: Data {
        get {
            access(keyPath: \.backgroundImageData)
            return UserDefaults.standard.data(forKey: SettingsKey.backgroundImageData.rawValue) ?? Data()
        }
        set {
            withMutation(keyPath: \.backgroundImageData) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.backgroundImageData.rawValue)
            }
        }
    }

    var ringDiameter: Double {
        get {
            access(keyPath: \.ringDiameter)
            return UserDefaults.standard.object(forKey: SettingsKey.ringDiameter.rawValue) as? Double ?? 60
        }
        set {
            withMutation(keyPath: \.ringDiameter) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.ringDiameter.rawValue)
            }
        }
    }

    // MARK: - Window Frame

    var capsuleWindowFrame: Data {
        get {
            access(keyPath: \.capsuleWindowFrame)
            return UserDefaults.standard.data(forKey: SettingsKey.capsuleWindowFrame.rawValue) ?? Data()
        }
        set {
            withMutation(keyPath: \.capsuleWindowFrame) {
                UserDefaults.standard.set(newValue, forKey: SettingsKey.capsuleWindowFrame.rawValue)
            }
        }
    }

    // MARK: - Actions

    func resetAll() {
        historyMaxCount = 200
        imageMaxSizeMB = 2
        pollingInterval = 0.5
        cleanupOnStartup = true
        dedupEnabled = true
        showHideShortcut = "cmd+shift+V"
        quickPasteShortcut = "cmd+shift+C"
        togglePinShortcut = ""
        iCloudSyncEnabled = false
        launchAtLogin = false
        showInMenuBar = true
        showFloatingPanel = true
        collapsedStyle = "capsule"
        hoverExpandDelay = 0.3
        hoverCollapseDelay = 1.0
        panelOpacityUnfocused = 0.6
        backgroundImageData = Data()
        ringDiameter = 60
        capsuleWindowFrame = Data()
    }

    func exportData(context: ModelContext) -> Data? {
        let descriptor = FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.timestamp)])
        guard let items = try? context.fetch(descriptor) else { return nil }
        let exports: [ClipItemExport] = items.map { item in
            var content: String?
            if item.contentTypeRaw == "image", let imageData = item.imageData {
                content = imageData.base64EncodedString()
            } else {
                content = item.textContent
            }
            return ClipItemExport(
                type: item.contentTypeRaw, content: content,
                fileName: item.imageFileName, timestamp: item.timestamp,
                pasteCount: item.pasteCount, sourceApp: item.sourceAppBundleID
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(exports)
    }

    func importData(_ data: Data, context: ModelContext) throws {
        let decoder = JSONDecoder()
        let imports = try decoder.decode([ClipItemExport].self, from: data)
        let existingDescriptor = FetchDescriptor<ClipItem>(sortBy: [])
        let existingItems = (try? context.fetch(existingDescriptor)) ?? []
        let existingTexts = Set(existingItems.compactMap { $0.textContent })
        let existingMD5s = Set(existingItems.compactMap { $0.imageMD5 })
        for item in imports {
            switch item.type {
            case "text":
                guard let text = item.content, !existingTexts.contains(text) else { continue }
                context.insert(ClipItem(timestamp: item.timestamp, pasteCount: item.pasteCount,
                    contentTypeRaw: "text", textContent: text, sourceAppBundleID: item.sourceApp))
            case "image":
                guard let base64 = item.content, let imageData = Data(base64Encoded: base64) else { continue }
                let md5 = ClipboardMonitor.md5Hash(imageData)
                guard !existingMD5s.contains(md5) else { continue }
                context.insert(ClipItem(timestamp: item.timestamp, pasteCount: item.pasteCount,
                    contentTypeRaw: "image", imageData: imageData, imageFileName: item.fileName,
                    imageMD5: md5, sourceAppBundleID: item.sourceApp))
            default: continue
            }
        }
        try context.save()
    }

    func clearAllHistory(context: ModelContext) {
        let descriptor = FetchDescriptor<ClipItem>(sortBy: [])
        guard let items = try? context.fetch(descriptor) else { return }
        for item in items { context.delete(item) }
        try? context.save()
    }
}
