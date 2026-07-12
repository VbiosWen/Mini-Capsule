import AppKit
import Carbon.HIToolbox

/// Parses a stored shortcut string ("cmd+shift+v") into a Carbon keyCode + modifier mask.
enum HotKeyParser {
    static func parse(_ shortcut: String) -> (keyCode: UInt32, modifiers: UInt32)? {
        let parts = shortcut.lowercased().split(separator: "+").map(String.init)
        var modifiers: UInt32 = 0
        var keyChar: Character?
        for part in parts {
            switch part {
            case "cmd", "command":     modifiers |= UInt32(cmdKey)
            case "shift":              modifiers |= UInt32(shiftKey)
            case "option", "opt", "alt": modifiers |= UInt32(optionKey)
            case "control", "ctrl":    modifiers |= UInt32(controlKey)
            default:                   keyChar = part.first   // last non-modifier wins
            }
        }
        guard let ch = keyChar, let code = keyCode(for: ch) else { return nil }
        return (code, modifiers)
    }

    /// ANSI virtual key codes for the characters used by shortcuts (a–z, 0–9).
    static func keyCode(for character: Character) -> UInt32? {
        let lower = Character(character.lowercased())
        return table[lower]
    }

    private static let table: [Character: UInt32] = [
        "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C),
        "d": UInt32(kVK_ANSI_D), "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F),
        "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H), "i": UInt32(kVK_ANSI_I),
        "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
        "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O),
        "p": UInt32(kVK_ANSI_P), "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R),
        "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T), "u": UInt32(kVK_ANSI_U),
        "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
        "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9),
    ]
}

/// Parses shortcuts and delegates registration to a HotKeyRegistering seam.
@MainActor
final class HotKeyCenter {
    private let registrar: HotKeyRegistering

    /// Default initializer creates a Carbon-backed registrar on the main actor.
    init() {
        self.registrar = CarbonHotKeyRegistrar()
    }

    /// Injected initializer for testing with a fake registrar.
    init(registrar: HotKeyRegistering) {
        self.registrar = registrar
    }

    /// Retained for existing call sites; the registrar installs its handler lazily.
    func installHandlerIfNeeded() { /* registrar installs on first register */ }

    func register(_ shortcut: String, action: @escaping () -> Void) {
        guard let (keyCode, modifiers) = HotKeyParser.parse(shortcut) else { return }
        registrar.register(keyCode: keyCode, modifiers: modifiers, handler: action)
    }

    func unregisterAll() { registrar.unregisterAll() }
}
