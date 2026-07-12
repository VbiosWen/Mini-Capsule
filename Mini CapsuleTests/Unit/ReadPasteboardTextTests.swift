import Testing
import Foundation
import AppKit
import SwiftData
@testable import Mini_Capsule

@MainActor
@Suite(.tags(.unit))
struct ReadPasteboardTextTests {
    private func monitor() -> ClipboardMonitor {
        ClipboardMonitor(settings: MockSettingsForSeams(), pasteboard: FakePasteboard())
    }
    private func t(_ raw: String) -> NSPasteboard.PasteboardType { .init(raw) }

    @Test func htmlConvertsToPlainText() {
        let pb = FakePasteboard()
        let html = t("public.html")
        pb.stubbedData[html] = Data("<b>hello</b> world".utf8)
        let result = monitor().readPasteboard(pb, types: [html])
        #expect(result?.type == "text")
        #expect(result?.text?.contains("hello world") == true)
    }

    @Test func whitespaceOnlyHTMLFallsThroughToString() {
        let pb = FakePasteboard()
        let html = t("public.html")
        pb.stubbedData[html] = Data("<p>   </p>".utf8)
        pb.stubbedStrings[.string] = "fallback text"
        // HTML plain text is whitespace → tier 5 skipped → tier 10 string used.
        let result = monitor().readPasteboard(pb, types: [html, .string])
        #expect(result?.text == "fallback text")
    }

    @Test func rtfConvertsToPlainText() {
        let pb = FakePasteboard()
        pb.stubbedData[.rtf] = Data("{\\rtf1\\ansi hello rtf}".utf8)
        let result = monitor().readPasteboard(pb, types: [.rtf])
        #expect(result?.type == "text")
        #expect(result?.text?.contains("hello rtf") == true)
    }

    @Test func tabularTextIsReadAsText() {
        let pb = FakePasteboard()
        pb.stubbedStrings[.tabularText] = "a\tb\tc"
        let result = monitor().readPasteboard(pb, types: [.tabularText])
        #expect(result?.text == "a\tb\tc")
    }

    @Test func publicURLIsReadAsText() {
        let pb = FakePasteboard()
        let url = t("public.url")
        pb.stubbedStrings[url] = "https://example.com"
        let result = monitor().readPasteboard(pb, types: [url])
        #expect(result?.text == "https://example.com")
    }

    @Test func plainStringIsFinalFallback() {
        let pb = FakePasteboard()
        pb.stubbedStrings[.string] = "just text"
        let result = monitor().readPasteboard(pb, types: [.string])
        #expect(result?.type == "text")
        #expect(result?.text == "just text")
    }

    @Test func unicodeAndEmptyStringHandled() {
        let pb = FakePasteboard()
        pb.stubbedStrings[.string] = "emoji 🎉 中文"
        #expect(monitor().readPasteboard(pb, types: [.string])?.text == "emoji 🎉 中文")

        let empty = FakePasteboard()
        empty.stubbedStrings[.string] = ""
        #expect(monitor().readPasteboard(empty, types: [.string])?.text == "")
    }
}
