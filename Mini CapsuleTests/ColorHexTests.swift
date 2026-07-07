// Mini CapsuleTests/ColorHexTests.swift
import Testing
import SwiftUI
@testable import Mini_Capsule

struct ColorHexTests {

    @Test func validHexParsesCorrectly() async throws {
        let color = Color(hex: "#FF0000")
        #expect(color != nil)
    }

    @Test func validSixCharHexParses() async throws {
        let color = Color(hex: "00FF00")
        #expect(color != nil)
    }

    @Test func invalidHexReturnsNil() async throws {
        let color = Color(hex: "GGGGGG")
        #expect(color == nil)
    }

    @Test func shortHexReturnsNil() async throws {
        let color = Color(hex: "FFF")
        #expect(color == nil)
    }

    @Test func toHexReturnsFormattedHex() async throws {
        let color = Color(hex: "#007AFF")
        #expect(color != nil)
        let hex = color?.toHex()
        #expect(hex?.hasPrefix("#") == true)
        #expect(hex?.count == 7)
    }
}
