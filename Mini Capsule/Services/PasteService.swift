// Mini Capsule/Services/PasteService.swift
import AppKit
import SwiftData
import CoreGraphics
import ApplicationServices

@MainActor
final class PasteService {
    static var isSelfPaste = false

    /// Copy item to clipboard only (no auto-paste). Updates usage stats.
    static func copyToClipboard(_ item: ClipItem) {
        isSelfPaste = true
        defer { isSelfPaste = false }

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
    }

    static func paste(_ item: ClipItem, context: ModelContext) {
        // Check accessibility permissions before attempting CGEvent simulation
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        guard AXIsProcessTrustedWithOptions(options) else {
            // Accessibility permissions not granted — paste will fail silently
            return
        }

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

        // Note: CGEventSource.keyCode(forKeyboardType:source:character:) is not available
        // in this SDK version. The hardcoded key code 0x09 (V) is QWERTY-specific.
        // For non-QWERTY layouts, a keyboard layout lookup would be needed.
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

        // Post events
        cmdDown?.post(tap: CGEventTapLocation.cghidEventTap)
        vDown?.post(tap: CGEventTapLocation.cghidEventTap)
        vUp?.post(tap: CGEventTapLocation.cghidEventTap)
        cmdUp?.post(tap: CGEventTapLocation.cghidEventTap)

        // Update paste stats
        item.pasteCount += 1
        item.lastPastedAt = Date()
        try? context.save()
    }
}
