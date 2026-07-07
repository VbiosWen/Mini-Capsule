// Mini CapsuleTests/PasteServiceTests.swift
import Testing
import AppKit
@testable import Mini_Capsule

@MainActor
struct PasteServiceTests {

    @Test func keyCodeForVReturnsNonZero() async throws {
        let keyCode = PasteService.keyCodeForV()
        // Should return a valid key code (>0) or the fallback 0x09
        #expect(keyCode != 0)
    }

    @Test func isSelfPasteDefaultsToFalse() async throws {
        #expect(PasteService.isSelfPaste == false)
    }
}
