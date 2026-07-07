// Mini Capsule/Settings/SettingsStore.swift
import SwiftUI
import SwiftData
import Foundation
import Combine

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
final class SettingsStore: ObservableObject, SettingsProtocol {
    // MARK: - Clipboard

    @AppStorage(SettingsKey.historyMaxCount.rawValue)
    var historyMaxCount: Int = 200 { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.imageMaxSizeMB.rawValue)
    var imageMaxSizeMB: Int = 2 { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.pollingInterval.rawValue)
    var pollingInterval: Double = 0.5 { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.cleanupOnStartup.rawValue)
    var cleanupOnStartup: Bool = true { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.dedupEnabled.rawValue)
    var dedupEnabled: Bool = true { didSet { objectWillChange.send() } }

    // MARK: - Shortcuts

    @AppStorage(SettingsKey.showHideShortcut.rawValue)
    var showHideShortcut: String = "cmd+shift+V" { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.quickPasteShortcut.rawValue)
    var quickPasteShortcut: String = "cmd+shift+C" { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.togglePinShortcut.rawValue)
    var togglePinShortcut: String = "" { didSet { objectWillChange.send() } }

    // MARK: - Advanced

    @AppStorage(SettingsKey.iCloudSyncEnabled.rawValue)
    var iCloudSyncEnabled: Bool = false { didSet { objectWillChange.send() } }

    // MARK: - General

    @AppStorage(SettingsKey.launchAtLogin.rawValue)
    var launchAtLogin: Bool = false { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.showInMenuBar.rawValue)
    var showInMenuBar: Bool = true { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.showFloatingPanel.rawValue)
    var showFloatingPanel: Bool = true { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.collapsedStyle.rawValue)
    var collapsedStyle: String = "capsule" { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.hoverExpandDelay.rawValue)
    var hoverExpandDelay: Double = 0.3 { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.hoverCollapseDelay.rawValue)
    var hoverCollapseDelay: Double = 1.0 { didSet { objectWillChange.send() } }

    // MARK: - Appearance

    @AppStorage(SettingsKey.panelOpacityUnfocused.rawValue)
    var panelOpacityUnfocused: Double = 0.6 { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.backgroundImageData.rawValue)
    var backgroundImageData: Data = Data() { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.dotColorMode.rawValue)
    var dotColorMode: String = "auto" { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.dotCustomColor.rawValue)
    var dotCustomColor: String = "#007AFF" { didSet { objectWillChange.send() } }

    @AppStorage(SettingsKey.capsuleWindowFrame.rawValue)
    var capsuleWindowFrame: Data = Data() { didSet { objectWillChange.send() } }

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
        dotColorMode = "auto"
        dotCustomColor = "#007AFF"
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
