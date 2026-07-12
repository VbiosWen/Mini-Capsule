import Testing
import Foundation
import SwiftData
import AppKit
@testable import Mini_Capsule

private final class MockSettings: SettingsProtocol {
    var historyMaxCount: Int = 200
    var imageMaxSizeMB: Int = 2
    var pollingInterval: Double = 0.5
    var cleanupOnStartup: Bool = true
    var dedupEnabled: Bool = true
    var showHideShortcut: String = ""
    var quickPasteShortcut: String = ""
    var togglePinShortcut: String = ""
    var iCloudSyncEnabled: Bool = false
    var launchAtLogin: Bool = false
    var showInMenuBar: Bool = true
    var showFloatingPanel: Bool = true
    var collapsedStyle: String = "capsule"
    var hoverExpandDelay: Double = 0.3
    var hoverCollapseDelay: Double = 1.0
    var panelOpacityUnfocused: Double = 0.6
    var backgroundImageData: Data = Data()
    var ringDiameter: Double = 30
    var capsuleWindowFrame: Data = Data()
    func resetAll() {}
    func exportData(context: ModelContext) -> Data? { nil }
    func importData(_ data: Data, context: ModelContext) throws {}
    func clearAllHistory(context: ModelContext) {}
}

@MainActor
@Suite(.tags(.unit))
struct ReadPasteboardFileTests {
    private func monitor() -> ClipboardMonitor {
        ClipboardMonitor(settings: MockSettings(), pasteboard: FakePasteboard())
    }

    private func t(_ raw: String) -> NSPasteboard.PasteboardType { .init(raw) }

    /// Create a real temp file so bookmarkData() succeeds; returns its URL.
    private func makeTempFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mc-\(UUID().uuidString).txt")
        try Data("hi".utf8).write(to: url)
        return url
    }

    @Test func legacyFilenamesTierReturnsFileWithBookmarks() throws {
        let url = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let pb = FakePasteboard()
        let legacy = t("NSFilenamesPboardType")
        pb.stubbedPropertyLists[legacy] = [url.path]

        let result = monitor().readPasteboard(pb, types: [legacy])
        #expect(result?.type == "file")
        #expect(result?.fileName == url.lastPathComponent)
        let bookmarks = PasteService.decodeFileBookmarks(try #require(result?.fileBookmarks))
        #expect(bookmarks.count == 1)
    }

    @Test func fileURLTierReturnsFileWithBookmarks() throws {
        let url = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let pb = FakePasteboard()
        pb.stubbedReadObjects = [url]
        let result = monitor().readPasteboard(pb, types: [.fileURL])
        #expect(result?.type == "file")
        #expect(result?.fileName == url.lastPathComponent)
    }

    @Test func nonexistentLegacyPathYieldsNil() {
        let pb = FakePasteboard()
        let legacy = t("NSFilenamesPboardType")
        pb.stubbedPropertyLists[legacy] = ["/does/not/exist-\(UUID().uuidString)"]
        // bookmarkData throws -> empty -> encodeFileBookmarks(nil) -> readPasteboard nil.
        #expect(monitor().readPasteboard(pb, types: [legacy]) == nil)
    }
}
