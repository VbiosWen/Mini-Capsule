import Testing
import AppKit
@testable import Mini_Capsule

@MainActor
@Suite(.tags(.integration))
struct HotKeyCenterIntegrationTests {
    @Test func registerParsesShortcutAndForwardsKeyCodeModifiers() {
        let registrar = FakeHotKeyRegistrar()
        let center = HotKeyCenter(registrar: registrar)
        var fired = false
        center.register("cmd+shift+v") { fired = true }

        let entry = registrar.registrations.first
        #expect(entry != nil)
        // 'v' key code from HotKeyParser + cmd|shift modifiers.
        let expected = HotKeyParser.parse("cmd+shift+v")
        #expect(entry?.keyCode == expected?.keyCode)
        #expect(entry?.modifiers == expected?.modifiers)

        registrar.simulateFire(keyCode: entry!.keyCode, modifiers: entry!.modifiers)
        #expect(fired)
    }

    @Test func invalidShortcutRegistersNothing() {
        let registrar = FakeHotKeyRegistrar()
        let center = HotKeyCenter(registrar: registrar)
        center.register("cmd+shift") { }   // no non-modifier key → parse nil
        #expect(registrar.registrations.isEmpty)
    }

    @Test func unregisterAllClearsRegistrar() {
        let registrar = FakeHotKeyRegistrar()
        let center = HotKeyCenter(registrar: registrar)
        center.register("cmd+c") { }
        center.unregisterAll()
        #expect(registrar.unregisterAllCount == 1)
    }
}
