// Mini Capsule/Services/PasteService.swift
import AppKit
import SwiftData
import CoreGraphics
import ApplicationServices
import Carbon

@MainActor
final class PasteService {
    /// The pasteboard changeCount produced by our own copy/paste, so the
    /// monitor can skip exactly that change even though it polls asynchronously.
    private static var suppressedChangeCount: Int?

    static func markSelfPaste() {
        suppressedChangeCount = NSPasteboard.general.changeCount
    }

    /// Returns true (and consumes the token) when `changeCount` is the change we produced.
    static func shouldSuppress(changeCount: Int) -> Bool {
        if suppressedChangeCount == changeCount {
            suppressedChangeCount = nil
            return true
        }
        return false
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

    /// Copy item to clipboard only (no auto-paste). Updates usage stats.
    static func copyToClipboard(_ item: ClipItem) {
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

        markSelfPaste()
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

        markSelfPaste()

        // Simulate Cmd+V via CGEvent
        let source = CGEventSource(stateID: .combinedSessionState)

        let cmdKey: CGKeyCode = 0x37
        let vKey: CGKeyCode = Self.keyCodeForV()

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
