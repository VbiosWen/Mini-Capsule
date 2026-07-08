// Mini Capsule/Utilities/ColorHex.swift
import SwiftUI
import AppKit

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        guard hex.count == 6,
              let num = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: Double((num >> 16) & 0xFF) / 255.0,
            green: Double((num >> 8) & 0xFF) / 255.0,
            blue: Double(num & 0xFF) / 255.0
        )
    }

    /// Deterministic color from a seed string. Same seed → same color.
    /// HSB tuned so both light and dark backgrounds show the color clearly.
    static func deterministic(from seed: String) -> Color {
        var hash: UInt64 = 0xcbf29ce484222325   // FNV-1a offset basis
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3           // FNV-1a prime
        }
        let hue = Double(hash & 0xFFFF) / 65535.0
        let sat = 0.55 + Double((hash >> 16) & 0xFFFF) / 65535.0 * 0.20
        let bri = 0.55 + Double((hash >> 32) & 0xFFFF) / 65535.0 * 0.15
        return Color(hue: hue, saturation: sat, brightness: bri)
    }

    func toHex() -> String {
        guard let components = NSColor(self).cgColor.components, components.count >= 3 else {
            return "#007AFF"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
