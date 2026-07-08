import Testing
import Carbon.HIToolbox
@testable import Mini_Capsule

struct HotKeyParserTests {
    @Test func parsesModifiersAndKey() {
        let r = HotKeyParser.parse("cmd+shift+v")
        #expect(r != nil)
        #expect(r?.keyCode == UInt32(kVK_ANSI_V))            // 9
        #expect(r?.modifiers == UInt32(cmdKey | shiftKey))
    }

    @Test func isCaseInsensitiveOnKey() {
        #expect(HotKeyParser.parse("cmd+shift+V")?.keyCode == HotKeyParser.parse("cmd+shift+v")?.keyCode)
    }

    @Test func returnsNilWhenNoBaseKey() {
        #expect(HotKeyParser.parse("cmd+shift") == nil)
        #expect(HotKeyParser.parse("") == nil)
    }

    @Test func parsesControlOptionAliases() {
        let r = HotKeyParser.parse("control+option+c")
        #expect(r?.modifiers == UInt32(controlKey | optionKey))
        #expect(r?.keyCode == UInt32(kVK_ANSI_C))            // 8
    }
}
