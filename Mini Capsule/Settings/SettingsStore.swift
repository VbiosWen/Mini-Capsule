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
final class SettingsStore: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    // MARK: - Clipboard

    @AppStorage("historyMaxCount") var historyMaxCount: Int = 200
    @AppStorage("imageMaxSizeMB") var imageMaxSizeMB: Int = 2  // 0 means unlimited
    @AppStorage("pollingInterval") var pollingInterval: Double = 0.5
    @AppStorage("cleanupOnStartup") var cleanupOnStartup: Bool = true
    @AppStorage("dedupEnabled") var dedupEnabled: Bool = true

    // MARK: - Shortcuts

    @AppStorage("showHideShortcut") var showHideShortcut: String = "cmd+shift+V"
    @AppStorage("quickPasteShortcut") var quickPasteShortcut: String = "cmd+shift+C"
    @AppStorage("togglePinShortcut") var togglePinShortcut: String = ""

    // MARK: - Advanced

    @AppStorage("iCloudSyncEnabled") var iCloudSyncEnabled: Bool = false

    // MARK: - General

    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("showInMenuBar") var showInMenuBar: Bool = true
    @AppStorage("showFloatingPanel") var showFloatingPanel: Bool = true
    @AppStorage("collapsedStyle") var collapsedStyle: String = "capsule"
    @AppStorage("hoverExpandDelay") var hoverExpandDelay: Double = 0.3
    @AppStorage("hoverCollapseDelay") var hoverCollapseDelay: Double = 1.0

    // MARK: - Appearance

    @AppStorage("panelOpacityUnfocused") var panelOpacityUnfocused: Double = 0.6
    @AppStorage("backgroundImageData") var backgroundImageData: Data = Data()
    @AppStorage("dotColorMode") var dotColorMode: String = "auto"
    @AppStorage("dotCustomColor") var dotCustomColor: String = "#007AFF"

    // MARK: - Actions

    /// Reset all settings to their default values.
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
    }

    /// Serialize all ClipItem records to JSON.
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
                type: item.contentTypeRaw,
                content: content,
                fileName: item.imageFileName,
                timestamp: item.timestamp,
                pasteCount: item.pasteCount,
                sourceApp: item.sourceAppBundleID
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(exports)
    }

    /// Import clip items from JSON, merging with existing data (dedup by content / MD5).
    func importData(_ data: Data, context: ModelContext) throws {
        let decoder = JSONDecoder()
        let imports = try decoder.decode([ClipItemExport].self, from: data)

        // Pre-fetch existing items for dedup
        let existingDescriptor = FetchDescriptor<ClipItem>(sortBy: [])
        let existingItems = (try? context.fetch(existingDescriptor)) ?? []
        let existingTexts = Set(existingItems.compactMap { $0.textContent })
        let existingMD5s = Set(existingItems.compactMap { $0.imageMD5 })

        for item in imports {
            switch item.type {
            case "text":
                guard let text = item.content, !existingTexts.contains(text) else { continue }
                let clip = ClipItem(
                    timestamp: item.timestamp,
                    pasteCount: item.pasteCount,
                    contentTypeRaw: "text",
                    textContent: text,
                    sourceAppBundleID: item.sourceApp
                )
                context.insert(clip)
            case "image":
                guard let base64 = item.content, let imageData = Data(base64Encoded: base64) else { continue }
                let md5 = ClipboardMonitor.md5Hash(imageData)
                guard !existingMD5s.contains(md5) else { continue }
                let clip = ClipItem(
                    timestamp: item.timestamp,
                    pasteCount: item.pasteCount,
                    contentTypeRaw: "image",
                    imageData: imageData,
                    imageFileName: item.fileName,
                    imageMD5: md5,
                    sourceAppBundleID: item.sourceApp
                )
                context.insert(clip)
            default:
                continue
            }
        }
        try context.save()
    }

    /// Delete all ClipItem records from SwiftData.
    func clearAllHistory(context: ModelContext) {
        let descriptor = FetchDescriptor<ClipItem>(sortBy: [])
        guard let items = try? context.fetch(descriptor) else { return }
        for item in items {
            context.delete(item)
        }
        try? context.save()
    }
}
