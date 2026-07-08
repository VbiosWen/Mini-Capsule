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
    // MARK: - Internal State

    private var data: SettingsData
    private let persistence = SettingsPersistence()

    // MARK: - Init

    init(data: SettingsData = SettingsData()) {
        self.data = data
    }

    // MARK: - Persistence

    /// Schedule an async write of the current settings snapshot to disk.
    private func persist() {
        let snapshot = data
        Task { [snapshot] in
            try? await persistence.save(snapshot)
        }
    }

    // MARK: - Clipboard

    var historyMaxCount: Int {
        get { data.historyMaxCount }
        set {
            data.historyMaxCount = newValue
            persist()
        }
    }

    var imageMaxSizeMB: Int {
        get { data.imageMaxSizeMB }
        set {
            data.imageMaxSizeMB = newValue
            persist()
        }
    }

    var pollingInterval: Double {
        get { data.pollingInterval }
        set {
            data.pollingInterval = newValue
            persist()
        }
    }

    var cleanupOnStartup: Bool {
        get { data.cleanupOnStartup }
        set {
            data.cleanupOnStartup = newValue
            persist()
        }
    }

    var dedupEnabled: Bool {
        get { data.dedupEnabled }
        set {
            data.dedupEnabled = newValue
            persist()
        }
    }

    // MARK: - Shortcuts

    var showHideShortcut: String {
        get { data.showHideShortcut }
        set {
            data.showHideShortcut = newValue
            persist()
        }
    }

    var quickPasteShortcut: String {
        get { data.quickPasteShortcut }
        set {
            data.quickPasteShortcut = newValue
            persist()
        }
    }

    var togglePinShortcut: String {
        get { data.togglePinShortcut }
        set {
            data.togglePinShortcut = newValue
            persist()
        }
    }

    // MARK: - Advanced

    var iCloudSyncEnabled: Bool {
        get { data.iCloudSyncEnabled }
        set {
            data.iCloudSyncEnabled = newValue
            persist()
        }
    }

    // MARK: - General

    var launchAtLogin: Bool {
        get { data.launchAtLogin }
        set {
            data.launchAtLogin = newValue
            persist()
        }
    }

    var showInMenuBar: Bool {
        get { data.showInMenuBar }
        set {
            data.showInMenuBar = newValue
            persist()
        }
    }

    var showFloatingPanel: Bool {
        get { data.showFloatingPanel }
        set {
            data.showFloatingPanel = newValue
            persist()
        }
    }

    var collapsedStyle: String {
        get { data.collapsedStyle }
        set {
            data.collapsedStyle = newValue
            persist()
        }
    }

    var hoverExpandDelay: Double {
        get { data.hoverExpandDelay }
        set {
            data.hoverExpandDelay = newValue
            persist()
        }
    }

    var hoverCollapseDelay: Double {
        get { data.hoverCollapseDelay }
        set {
            data.hoverCollapseDelay = newValue
            persist()
        }
    }

    // MARK: - Appearance

    var panelOpacityUnfocused: Double {
        get { data.panelOpacityUnfocused }
        set {
            data.panelOpacityUnfocused = newValue
            persist()
        }
    }

    var backgroundImageData: Data {
        get { data.backgroundImageData }
        set {
            data.backgroundImageData = newValue
            persist()
        }
    }

    var ringDiameter: Double {
        get { data.ringDiameter }
        set {
            data.ringDiameter = newValue
            persist()
        }
    }

    // MARK: - Window Frame

    var capsuleWindowFrame: Data {
        get { data.capsuleWindowFrame }
        set {
            data.capsuleWindowFrame = newValue
            persist()
        }
    }

    // MARK: - Actions

    func resetAll() {
        data = SettingsData()
        persist()
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
