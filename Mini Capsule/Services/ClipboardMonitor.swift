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

    // Burst polling: after detecting a change, poll rapidly (3× @ 50 ms)
    // to catch successive Cmd+C presses that would otherwise be missed
    // between normal timer ticks.
    private var burstCount = 0
    private var burstWorkItem: DispatchWorkItem?

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

    /// After a change is detected, poll rapidly for a short burst to catch
    /// successive copies that land between normal timer ticks.
    private func scheduleBurstPoll() {
        guard burstCount < 3 else {
            burstCount = 0
            return
        }
        burstCount += 1
        burstWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.checkPasteboard()
            }
        }
        burstWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50), execute: workItem)
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
              let content = readPasteboard(pasteboard, types: pbTypes) else {
            #if DEBUG
            let available = pasteboard.types?.map(\.rawValue) ?? []
            if !available.isEmpty {
                NSLog("[MiniCapsule] Pasteboard changed (CC=%d) but no content read. Available types: %@",
                      currentChangeCount, available.joined(separator: ", "))
            }
            #endif
            // Still schedule burst — an intermediate clearContents may have
            // emptied the board just before the real write.
            scheduleBurstPoll()
            return
        }

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
                    scheduleBurstPoll()
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
                scheduleBurstPoll()
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
                scheduleBurstPoll()
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
                    scheduleBurstPoll()
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
        scheduleBurstPoll()
    }

    private func readPasteboard(
        _ pb: NSPasteboard,
        types: [NSPasteboard.PasteboardType]
    ) -> (type: String, text: String?, image: Data?, fileBookmarks: Data?, fileName: String?)? {
        // ── nspasteboard.org community standards ──────────────────────────
        // Respect password-manager and transient-content conventions.
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        let autoGenerated = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
        if types.contains(concealed) || types.contains(transient) || types.contains(autoGenerated) {
            return nil  // Never store sensitive / transient / auto-generated content.
        }

        // ── 1. Known image UTIs — preserves original format (GIF, etc.) ──
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

        // ── 2. NSImage fallback — WeChat, custom types ────────────────────
        if let nsImages = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let nsImage = nsImages.first {
            let pngData = nsImageToPNGData(nsImage)
            let image = capImageSize(pngData, maxBytes: maxImageBytes)
            let fileName = extractFileName(from: pb, types: types)
            return ("image", nil, image, nil, fileName)
        }

        // ── 3. Legacy file list (NSFilenamesPboardType) ───────────────────
        let legacyFileType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if types.contains(legacyFileType),
           let paths = pb.propertyList(forType: legacyFileType) as? [String],
           !paths.isEmpty {
            let urls = paths.map { URL(fileURLWithPath: $0) }
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

        // ── 4. fileURL — security-scoped bookmarks ────────────────────────
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

        // ── 5. HTML — convert to plain text ───────────────────────────────
        let htmlType = NSPasteboard.PasteboardType("public.html")
        if types.contains(htmlType), let htmlData = pb.data(forType: htmlType),
           let plain = htmlToPlainText(htmlData), !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ("text", plain, nil, nil, nil)
        }

        // ── 6. RTF — convert to plain text ────────────────────────────────
        if types.contains(.rtf), let rtfData = pb.data(forType: .rtf),
           let plain = rtfToPlainText(rtfData), !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ("text", plain, nil, nil, nil)
        }

        // ── 7. Tab-separated text (spreadsheets) ──────────────────────────
        if types.contains(.tabularText),
           let text = pb.string(forType: .tabularText) {
            return ("text", text, nil, nil, nil)
        }

        // ── 8. Non-file URL — capture as text ─────────────────────────────
        // .fileURL is handled above (tier 4); public.url covers web URLs.
        let urlType = NSPasteboard.PasteboardType("public.url")
        if types.contains(urlType),
           let urlString = pb.string(forType: urlType) {
            return ("text", urlString, nil, nil, nil)
        }

        // ── 9. PDF — capture raw data (stored as image for display) ───────
        if types.contains(.pdf), let pdfData = pb.data(forType: .pdf) {
            let fileName = extractFileName(from: pb, types: types) ?? "PDF-\(UUID().uuidString.prefix(4)).pdf"
            return ("image", nil, pdfData, nil, fileName)
        }

        // ── 10. Plain text — final fallback ───────────────────────────────
        if let text = pb.string(forType: .string) {
            return ("text", text, nil, nil, nil)
        }

        // ── No recognised type ────────────────────────────────────────────
        return nil
    }

    // MARK: - Helpers

    /// Convert HTML pasteboard data to plain text via NSAttributedString.
    private func htmlToPlainText(_ data: Data) -> String? {
        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        return try? NSAttributedString(data: data, options: opts, documentAttributes: nil).string
    }

    /// Convert RTF pasteboard data to plain text via NSAttributedString.
    private func rtfToPlainText(_ data: Data) -> String? {
        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf,
        ]
        return try? NSAttributedString(data: data, options: opts, documentAttributes: nil).string
    }

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
