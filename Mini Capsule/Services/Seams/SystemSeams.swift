import AppKit
import ApplicationServices
import CoreGraphics

/// Identity of the frontmost application (source app for a capture).
protocol FrontmostAppProviding {
    var bundleID: String? { get }
    var appName: String? { get }
}

struct RealFrontmostApp: FrontmostAppProviding {
    var bundleID: String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    var appName: String? { NSWorkspace.shared.frontmostApplication?.localizedName }
}

/// Whether the process is trusted for Accessibility (needed to inject keystrokes).
protocol AccessibilityChecking {
    var isTrusted: Bool { get }
}

struct RealAccessibility: AccessibilityChecking {
    var isTrusted: Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options)
    }
}

/// Injects a synthetic Cmd+V. Production posts CGEvents; tests record the call.
protocol KeyInjecting {
    func pasteViaCommandV()
}

struct RealKeyInjector: KeyInjecting {
    func pasteViaCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cmdKey: CGKeyCode = 0x37
        let vKey: CGKeyCode = PasteService.keyCodeForV()

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKey, keyDown: false)

        let cmdFlag = CGEventFlags.maskCommand.rawValue
        cmdDown?.flags = CGEventFlags(rawValue: cmdFlag)
        vDown?.flags = CGEventFlags(rawValue: cmdFlag)
        vUp?.flags = CGEventFlags(rawValue: cmdFlag)
        cmdUp?.flags = CGEventFlags(rawValue: 0)

        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }
}
