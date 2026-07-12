import AppKit
@testable import Mini_Capsule

/// In-memory pasteboard for deterministic capture/paste tests.
final class FakePasteboard: PasteboardReading, PasteboardWriting {
    // Read stubs
    var stubbedChangeCount = 1
    var stubbedTypes: [NSPasteboard.PasteboardType]? = nil
    var stubbedStrings: [NSPasteboard.PasteboardType: String] = [:]
    var stubbedData: [NSPasteboard.PasteboardType: Data] = [:]
    var stubbedPropertyLists: [NSPasteboard.PasteboardType: Any] = [:]
    var stubbedReadObjects: [Any] = []

    // Write recordings
    private(set) var clearCount = 0
    private(set) var writtenStrings: [NSPasteboard.PasteboardType: String] = [:]
    private(set) var writtenData: [NSPasteboard.PasteboardType: Data] = [:]
    private(set) var writtenPropertyLists: [NSPasteboard.PasteboardType: Any] = [:]
    private(set) var writtenObjectCount = 0

    var changeCount: Int { stubbedChangeCount }
    var types: [NSPasteboard.PasteboardType]? { stubbedTypes }
    func data(forType type: NSPasteboard.PasteboardType) -> Data? { stubbedData[type] }
    func string(forType type: NSPasteboard.PasteboardType) -> String? { stubbedStrings[type] }
    func propertyList(forType type: NSPasteboard.PasteboardType) -> Any? { stubbedPropertyLists[type] }
    func readObjects(forClasses classArray: [AnyClass],
                     options: [NSPasteboard.ReadingOptionKey: Any]?) -> [Any]? {
        stubbedReadObjects.isEmpty ? nil : stubbedReadObjects
    }

    @discardableResult func clearContents() -> Int { clearCount += 1; stubbedChangeCount += 1; return stubbedChangeCount }
    @discardableResult func setString(_ s: String, forType t: NSPasteboard.PasteboardType) -> Bool { clearCount += 1; writtenStrings[t] = s; stubbedChangeCount += 1; return true }
    @discardableResult func setData(_ d: Data?, forType t: NSPasteboard.PasteboardType) -> Bool { clearCount += 1; writtenData[t] = d; stubbedChangeCount += 1; return true }
    @discardableResult func setPropertyList(_ p: Any, forType t: NSPasteboard.PasteboardType) -> Bool { clearCount += 1; writtenPropertyLists[t] = p; stubbedChangeCount += 1; return true }
    @discardableResult func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool { clearCount += 1; writtenObjectCount += objects.count; stubbedChangeCount += 1; return true }
}

struct FakeWorkspace: FrontmostAppProviding {
    var bundleID: String?
    var appName: String?
}

struct FakeAccessibility: AccessibilityChecking {
    let isTrusted: Bool
}

final class FakeKeyInjector: KeyInjecting {
    private(set) var pasteCallCount = 0
    func pasteViaCommandV() { pasteCallCount += 1 }
}

final class FakeScheduler: Scheduling {
    final class Token: Cancellable {
        var cancelled = false
        func cancel() { cancelled = true }
    }
    struct Pending { let token: Token; let block: () -> Void }
    private(set) var afterBlocks: [Pending] = []
    private(set) var everyBlocks: [Pending] = []

    @discardableResult func after(_ delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
        let t = Token(); afterBlocks.append(Pending(token: t, block: block)); return t
    }
    @discardableResult func every(_ interval: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
        let t = Token(); everyBlocks.append(Pending(token: t, block: block)); return t
    }
    /// Fire all non-cancelled one-shot blocks (simulates the delay elapsing).
    func fireAfter() { afterBlocks.filter { !$0.token.cancelled }.forEach { $0.block() } }
    /// Fire one tick of every repeating block.
    func tick() { everyBlocks.filter { !$0.token.cancelled }.forEach { $0.block() } }
}

@MainActor
final class FakeHotKeyRegistrar: HotKeyRegistering {
    struct Registration { let keyCode: UInt32; let modifiers: UInt32; let handler: () -> Void }
    private(set) var registrations: [Registration] = []
    private(set) var unregisterAllCount = 0

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        registrations.append(Registration(keyCode: keyCode, modifiers: modifiers, handler: handler))
        return true
    }
    func unregisterAll() { unregisterAllCount += 1; registrations.removeAll() }

    /// Test helper: invoke the handler registered for this key/modifier combo.
    func simulateFire(keyCode: UInt32, modifiers: UInt32) {
        registrations.first { $0.keyCode == keyCode && $0.modifiers == modifiers }?.handler()
    }
}
