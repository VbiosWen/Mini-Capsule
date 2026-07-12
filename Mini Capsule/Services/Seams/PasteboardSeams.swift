import AppKit

/// Read side of NSPasteboard, injectable for tests.
protocol PasteboardReading: AnyObject {
    var changeCount: Int { get }
    var types: [NSPasteboard.PasteboardType]? { get }
    func data(forType type: NSPasteboard.PasteboardType) -> Data?
    func string(forType type: NSPasteboard.PasteboardType) -> String?
    func propertyList(forType type: NSPasteboard.PasteboardType) -> Any?
    func readObjects(forClasses classArray: [AnyClass],
                     options: [NSPasteboard.ReadingOptionKey: Any]?) -> [Any]?
}

/// Write side of NSPasteboard, injectable for tests.
protocol PasteboardWriting: AnyObject {
    var changeCount: Int { get }
    @discardableResult func clearContents() -> Int
    @discardableResult func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool
    @discardableResult func setData(_ data: Data?, forType type: NSPasteboard.PasteboardType) -> Bool
    @discardableResult func setPropertyList(_ plist: Any, forType type: NSPasteboard.PasteboardType) -> Bool
    @discardableResult func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool
}

// NSPasteboard's real signatures already satisfy both protocols.
extension NSPasteboard: PasteboardReading, PasteboardWriting {}
