// Mini Capsule/Services/PasteService.swift
import AppKit
import SwiftData
import CoreGraphics
import ApplicationServices
import Carbon

@MainActor
final class PasteService {
    // Suppression state now lives in SelfPasteTracker (injectable, testable).
    static func beginSelfPaste() -> Int { NSPasteboard.general.changeCount }

    static func endSelfPaste(begin: Int) {
        let end = NSPasteboard.general.changeCount
        SelfPasteTracker.shared.markRange(begin: begin, end: end)
    }

    static func shouldSuppress(changeCount: Int) -> Bool {
        SelfPasteTracker.shared.shouldSuppress(changeCount: changeCount)
    }

    /// Resolve bookmarks → URLs and write them to the pasteboard as proper file references.
    /// Uses NSPasteboardItem with explicit UTI types so Finder and other apps can paste the actual files.
    private static func writeFileItemsToPasteboard(_ item: ClipItem, pasteboard: PasteboardWriting) {
        guard let bookmarkData = item.fileBookmarks else { return }

        let bookmarks = Self.decodeFileBookmarks(bookmarkData)
        var isStale = false
        let urls: [URL] = bookmarks.compactMap {
            try? URL(resolvingBookmarkData: $0, options: [], bookmarkDataIsStale: &isStale)
        }
        guard !urls.isEmpty else { return }

        // Also set the legacy file-names type for older apps that expect it.
        // NSFilenamesPboardType = "NSFilenamesPboardType"
        pasteboard.setPropertyList(
            urls.map { $0.path },
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
        )

        // Write each file URL as an explicit NSPasteboardItem for maximum compatibility.
        let pbItems: [NSPasteboardItem] = urls.map { url in
            let pbItem = NSPasteboardItem()
            // The UTI for a file URL on pasteboard is public.file-url.
            // NSPasteboardItem expects a property-list-compatible value: the URL string.
            pbItem.setString(url.absoluteString, forType: .fileURL)
            return pbItem
        }
        pasteboard.writeObjects(pbItems)
    }

    /// Dynamically resolve the key code for the "V" character.
    /// Uses TIS + UCKeyTranslate for keyboard-layout-aware lookup,
    /// falling back to QWERTY 0x09 if resolution fails.
    static func keyCodeForV() -> CGKeyCode {
        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return 0x09
        }
        let keyboardLayout = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        let targetChar: UniChar = UniChar(Character("v").unicodeScalars.first?.value ?? 0x0076)
        var deadKeyState: UInt32 = 0
        return keyboardLayout.withUnsafeBytes { ptr -> CGKeyCode in
            guard let base = ptr.baseAddress else { return 0x09 }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            var chars = [UniChar](repeating: 0, count: 4)
            var stringLength: Int = 0
            for kc in UInt16(0)..<UInt16(128) {
                stringLength = 0
                let status = UCKeyTranslate(
                    layout,
                    kc,
                    UInt16(kUCKeyActionDown),
                    0,
                    UInt32(LMGetKbdType()),
                    UInt32(kUCKeyTranslateNoDeadKeysMask),
                    &deadKeyState,
                    chars.count,
                    &stringLength,
                    &chars
                )
                if status == 0 && stringLength > 0 && chars[0] == targetChar {
                    return CGKeyCode(kc)
                }
            }
            return 0x09
        }
    }

    /// Decode a `fileBookmarks` blob. New format is a JSON-encoded `[Data]`
    /// (one element per URL). Legacy blobs were a single raw bookmark
    /// `Data`; those are returned as `[data]` so old items still paste.
    static func decodeFileBookmarks(_ data: Data) -> [Data] {
        if let arr = try? JSONDecoder().decode([Data].self, from: data), !arr.isEmpty {
            return arr
        }
        return [data]
    }

    static func copyToClipboard(_ item: ClipItem,
                                pasteboard: PasteboardWriting = NSPasteboard.general,
                                selfPaste: SelfPasteTracker = .shared,
                                log: LogSink = Log.shared) {
        let begin = pasteboard.changeCount
        pasteboard.clearContents()
        switch item.contentTypeRaw {
        case "text":  pasteboard.setString(item.textContent ?? "", forType: .string)
        case "image": if let data = item.imageData { pasteboard.setData(data, forType: .png) }
        case "file":  writeFileItemsToPasteboard(item, pasteboard: pasteboard)
        default: break
        }
        let end = pasteboard.changeCount
        selfPaste.markRange(begin: begin, end: end)
        log.log(.paste, .info, "copyToClipboard", metadata: ["type": item.contentTypeRaw])
    }

    static func paste(_ item: ClipItem,
                      context: ModelContext,
                      pasteboard: PasteboardWriting = NSPasteboard.general,
                      accessibility: AccessibilityChecking = RealAccessibility(),
                      keyInjector: KeyInjecting = RealKeyInjector(),
                      selfPaste: SelfPasteTracker = .shared,
                      log: LogSink = Log.shared) {
        guard accessibility.isTrusted else {
            log.log(.paste, .error, "paste skipped: accessibility not trusted",
                    metadata: ["type": item.contentTypeRaw])
            return
        }
        let begin = pasteboard.changeCount
        pasteboard.clearContents()
        switch item.contentTypeRaw {
        case "text":  pasteboard.setString(item.textContent ?? "", forType: .string)
        case "image": if let data = item.imageData { pasteboard.setData(data, forType: .png) }
        case "file":  writeFileItemsToPasteboard(item, pasteboard: pasteboard)
        default: break
        }
        let end = pasteboard.changeCount
        selfPaste.markRange(begin: begin, end: end)

        keyInjector.pasteViaCommandV()

        item.pasteCount += 1
        item.lastPastedAt = Date()
        do { try context.save() }
        catch { log.log(.paste, .error, "paste stat save failed", metadata: ["error": "\(error)"]) }
        log.log(.paste, .info, "paste", metadata: ["type": item.contentTypeRaw, "count": "\(item.pasteCount)"])
    }
}
