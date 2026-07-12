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
