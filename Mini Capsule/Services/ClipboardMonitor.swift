// Mini Capsule/Services/ClipboardMonitor.swift
import AppKit
import SwiftData
import Combine
import CryptoKit

@MainActor
final class ClipboardMonitor: ObservableObject {
    private let settings: SettingsProtocol
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private(set) var context: ModelContext?

    init(settings: SettingsProtocol) {
        self.settings = settings
    }

    private var currentPollingInterval: TimeInterval {
        return settings.pollingInterval > 0 ? settings.pollingInterval : 0.5
    }

    private var maxImageBytes: Int {
        switch settings.imageMaxSizeMB {
        case 1: return 1_000_000
        case 5: return 5_000_000
        case 0: return Int.max
        default: return 2_000_000
        }
    }

    private var maxHistoryCount: Int {
        return settings.historyMaxCount >= 50 ? settings.historyMaxCount : 200
    }

    private var isDedupEnabled: Bool {
        return settings.dedupEnabled
    }

    func start(context: ModelContext) {
        self.context = context
        lastChangeCount = NSPasteboard.general.changeCount
        restartTimer()
        observeSettings()
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: currentPollingInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                self?.checkPasteboard()
            }
        }
    }

    private func observeSettings() {
        NotificationCenter.default.addObserver(
            forName: .pollingIntervalDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restartTimer()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        context = nil
    }

    private func checkPasteboard() {
        guard let context = context else { return }
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount

        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        // Skip changes we produced ourselves (copy/paste), even across the poll gap.
        if PasteService.shouldSuppress(changeCount: currentChangeCount) { return }

        guard let pbTypes = pasteboard.types,
              let content = readPasteboard(pasteboard, types: pbTypes) else { return }

        // MD5-based dedup for images
        if content.type == "image", let imageData = content.image {
            if isDedupEnabled {
                let md5 = Self.md5Hash(imageData)
                let imagePredicate = #Predicate<ClipItem> { $0.contentTypeRaw == "image" && $0.imageMD5 == md5 }
                let existing = try? context.fetch(FetchDescriptor<ClipItem>(predicate: imagePredicate))
                if let existingItem = existing?.first {
                    existingItem.timestamp = Date()
                    try? context.save()
                    NotificationCenter.default.post(name: .clipItemsDidChange, object: nil)
                    return
                }

                // Enforce max count cap
                Self.enforceCap(context: context, maxCount: maxHistoryCount)

                let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                let appName = NSWorkspace.shared.frontmostApplication?.localizedName
                let fileName = content.fileName ?? "\(appName ?? "未知")-\(UUID().uuidString.prefix(4))"
                let thumbnail = Self.generateThumbnail(imageData)

                let item = ClipItem(
                    timestamp: Date(),
                    contentTypeRaw: content.type,
                    imageData: imageData,
                    imageThumbnail: thumbnail,
                    imageFileName: fileName,
                    imageMD5: md5,
                    sourceAppBundleID: sourceApp
                )
                context.insert(item)
                try? context.save()
                NotificationCenter.default.post(name: .clipItemsDidChange, object: nil)
                return
            } else {
                // No dedup — always insert
                Self.enforceCap(context: context, maxCount: maxHistoryCount)
                let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                let appName = NSWorkspace.shared.frontmostApplication?.localizedName
                let fileName = content.fileName ?? "\(appName ?? "未知")-\(UUID().uuidString.prefix(4))"
                let thumbnail = Self.generateThumbnail(imageData)
                let item = ClipItem(
                    timestamp: Date(),
                    contentTypeRaw: content.type,
                    imageData: imageData,
                    imageThumbnail: thumbnail,
                    imageFileName: fileName,
                    imageMD5: Self.md5Hash(imageData),
                    sourceAppBundleID: sourceApp
                )
                context.insert(item)
                try? context.save()
                NotificationCenter.default.post(name: .clipItemsDidChange, object: nil)
                return
            }
        }

        // Text/image dedup by content (existing logic)
        if isDedupEnabled {
            if let latest = try? context.fetch(
                FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
            ).first {
                switch (latest.contentTypeRaw, content.type) {
                case ("text", "text") where latest.textContent == content.text:
                    latest.timestamp = Date()
                    try? context.save()
                    NotificationCenter.default.post(name: .clipItemsDidChange, object: nil)
                    return
                default:
                    break
                }
            }
        }

        // Enforce max count cap
        Self.enforceCap(context: context, maxCount: maxHistoryCount)

        let item = ClipItem(
            timestamp: Date(),
            contentTypeRaw: content.type,
            textContent: content.text,
            imageFileName: content.type == "file" ? content.fileName : nil,
            fileBookmarks: content.fileBookmarks,
            sourceAppBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        context.insert(item)
        try? context.save()
        NotificationCenter.default.post(name: .clipItemsDidChange, object: nil)
    }

    private func readPasteboard(
        _ pb: NSPasteboard,
        types: [NSPasteboard.PasteboardType]
    ) -> (type: String, text: String?, image: Data?, fileBookmarks: Data?, fileName: String?)? {
        // 1. Try known image UTIs first — preserves original format (GIF animation, etc.)
        let imageUTIs: [NSPasteboard.PasteboardType] = [
            .png,
            .tiff,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("com.compuserve.gif"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("public.heif"),
            NSPasteboard.PasteboardType("com.microsoft.bmp"),
        ]
        for uti in imageUTIs {
            if types.contains(uti), let data = pb.data(forType: uti) {
                let image = capImageSize(data, maxBytes: maxImageBytes)
                let fileName = extractFileName(from: pb, types: types)
                return ("image", nil, image, nil, fileName)
            }
        }

        // 2. Fallback: NSImage generic reader — covers WeChat and other custom types
        if let nsImages = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let nsImage = nsImages.first {
            let pngData = nsImageToPNGData(nsImage)
            let image = capImageSize(pngData, maxBytes: maxImageBytes)
            let fileName = extractFileName(from: pb, types: types)
            return ("image", nil, image, nil, fileName)
        }

        // 3. fileURL — capture every URL on the pasteboard as its own bookmark.
        if types.contains(.fileURL),
           let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            let bookmarks: [Data] = urls.compactMap {
                try? $0.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            }
            guard let encoded = Self.encodeFileBookmarks(bookmarks) else { return nil }
            let firstName = urls.first?.lastPathComponent
            return ("file", nil, nil, encoded, firstName)
        }

        // 4. plain text
        if let text = pb.string(forType: .string) {
            return ("text", text, nil, nil, nil)
        }
        return nil
    }

    // MARK: - Helpers

    /// Convert NSImage to PNG Data. Used only in the fallback path
    /// (custom pasteboard types like WeChat) — known UTIs preserve original format.
    func nsImageToPNGData(_ nsImage: NSImage) -> Data {
        autoreleasepool {
            let tiff = nsImage.tiffRepresentation
            guard let tiff,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:])
            else { return tiff ?? Data() }
            return png
        }
    }

    /// Decode `data`, redraw at `maxDimension` (longest side), and return PNG bytes.
    /// Used at capture time for the row-preview thumbnail column, and lazily by
    /// legacy items on first render. Wrapped in `autoreleasepool` so the transient
    /// NSImage / NSBitmapImageRep drop as soon as this returns.
    nonisolated static func generateThumbnail(_ data: Data, maxDimension: CGFloat = 72) -> Data? {
        autoreleasepool {
            guard let source = NSImage(data: data) else { return nil }
            let src = source.size
            guard src.width > 0, src.height > 0 else { return nil }
            let longest = max(src.width, src.height)
            let scale = min(1.0, maxDimension / longest)
            let target = NSSize(width: src.width * scale, height: src.height * scale)

            let out = NSImage(size: target)
            out.lockFocus()
            source.draw(in: NSRect(origin: .zero, size: target),
                        from: NSRect(origin: .zero, size: src),
                        operation: .copy, fraction: 1.0)
            out.unlockFocus()

            guard let tiff = out.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:])
            else { return nil }
            return png
        }
    }

    private func extractFileName(from pb: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> String? {
        // Try to extract filename if fileURL is also present alongside the image
        if types.contains(.fileURL),
           let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first {
            return firstURL.lastPathComponent
        }
        return nil
    }

    /// Encode `[Data]` bookmarks as JSON for the `fileBookmarks` field.
    /// Returns nil for an empty array so callers can early-out cleanly.
    static func encodeFileBookmarks(_ bookmarks: [Data]) -> Data? {
        guard !bookmarks.isEmpty else { return nil }
        return try? JSONEncoder().encode(bookmarks)
    }

    static func md5Hash(_ data: Data) -> String {
        CryptoKit.Insecure.MD5.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    private func capImageSize(_ data: Data, maxBytes: Int) -> Data {
        autoreleasepool {
            guard data.count > maxBytes,
                  let image = NSImage(data: data) else { return data }
            let scale = sqrt(Double(maxBytes) / Double(data.count))
            let newSize = NSSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            let resized = NSImage(size: newSize)
            resized.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: newSize),
                       from: NSRect(origin: .zero, size: image.size),
                       operation: .copy, fraction: 1.0)
            resized.unlockFocus()
            guard let tiff = resized.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
            else { return data }
            return jpeg
        }
    }

    static func enforceCap(context: ModelContext, maxCount: Int) {
        guard let items = try? context.fetch(FetchDescriptor<ClipItem>(sortBy: [])),
              items.count >= maxCount else { return }
        // Called before inserting the new item: remove enough to leave room for one.
        let overflow = items.count - maxCount + 1
        let deletable = items
            .filter { !$0.isPinned }
            .sorted { $0.pasteCount < $1.pasteCount }   // least-used first
        for item in deletable.prefix(overflow) {        // prefix() is safe if overflow > count
            context.delete(item)
        }
    }
}
