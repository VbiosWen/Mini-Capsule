// Mini Capsule/Services/PasteService.swift
import AppKit
import SwiftData
import CoreGraphics

@MainActor
final class PasteService {
    static var isSelfPaste = false

    static func paste(_ item: ClipItem, context: ModelContext) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.contentTypeRaw {
        case "text":
            pasteboard.setString(item.textContent ?? "", forType: .string)
        case "image":
            if let data = item.imageData {
                pasteboard.setData(data, forType: .png)
            }
        case "file":
            if let bookmarkData = item.fileBookmarks {
                var isStale = false
                if let url = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [],
                    bookmarkDataIsStale: &isStale
                ) {
                    pasteboard.writeObjects([url as NSURL])
                }
            }
        default:
            break
        }

        // Mark to prevent self-capture
        isSelfPaste = true
        defer { isSelfPaste = false }

        // Simulate Cmd+V via CGEvent
        let source = CGEventSource(stateID: .combinedSessionState)

        let cmdKey: CGKeyCode = 0x37
        let vKey: CGKeyCode = 0x09

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)

        let cmdFlag = CGEventFlags.maskCommand.rawValue
        cmdDown?.flags = CGEventFlags(rawValue: cmdFlag)
        vDown?.flags = CGEventFlags(rawValue: cmdFlag)
        vUp?.flags = CGEventFlags(rawValue: cmdFlag)
        cmdUp?.flags = CGEventFlags(rawValue: 0)

        // Post events with small delays
        cmdDown?.post(tap: .cghidEventTap)
        usleep(10_000)
        vDown?.post(tap: .cghidEventTap)
        usleep(10_000)
        vUp?.post(tap: .cghidEventTap)
        usleep(10_000)
        cmdUp?.post(tap: .cghidEventTap)

        // Update paste stats
        item.pasteCount += 1
        item.lastPastedAt = Date()
        try? context.save()
    }
}
