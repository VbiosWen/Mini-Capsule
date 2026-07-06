// Mini Capsule/Services/ClipboardMonitor.swift
import AppKit
import SwiftData
import Combine

@MainActor
final class ClipboardMonitor: ObservableObject {
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var context: ModelContext?

    func start(context: ModelContext) {
        self.context = context
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { [weak self] in
                self?.checkPasteboard()
            }
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

        // Skip self-triggered pasteboard changes
        guard !PasteService.isSelfPaste else { return }

        guard let pbTypes = pasteboard.types,
              let content = readPasteboard(pasteboard, types: pbTypes) else { return }

        // Deduplicate against most recent item
        if let latest = try? context.fetch(
            FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        ).first {
            switch (latest.contentTypeRaw, content.type) {
            case ("text", "text") where latest.textContent == content.text:
                latest.timestamp = Date()
                try? context.save()
                return
            case ("image", "image") where latest.imageData == content.image:
                latest.timestamp = Date()
                try? context.save()
                return
            default:
                break
            }
        }

        // Enforce 200 item cap
        enforceCap(context: context, maxCount: 200)

        let item = ClipItem(
            timestamp: Date(),
            contentTypeRaw: content.type,
            textContent: content.text,
            imageData: content.image,
            fileBookmarks: content.fileBookmarks,
            sourceAppBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        context.insert(item)
        try? context.save()
    }

    private func readPasteboard(
        _ pb: NSPasteboard,
        types: [NSPasteboard.PasteboardType]
    ) -> (type: String, text: String?, image: Data?, fileBookmarks: Data?)? {
        if types.contains(.fileURL),
           let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first {
            let bookmarks = try? firstURL.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return ("file", nil, nil, bookmarks)
        }
        if types.contains(.png), let data = pb.data(forType: .png) {
            let image = capImageSize(data, maxBytes: 2_000_000)
            return ("image", nil, image, nil)
        }
        if let text = pb.string(forType: .string) {
            return ("text", text, nil, nil)
        }
        return nil
    }

    private func capImageSize(_ data: Data, maxBytes: Int) -> Data {
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

    private func enforceCap(context: ModelContext, maxCount: Int) {
        let allItems = FetchDescriptor<ClipItem>(sortBy: [])
        guard let items = try? context.fetch(allItems),
              items.count >= maxCount else { return }

        // Sort: pinned first, then by paste count descending
        let sorted = items.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.pasteCount > b.pasteCount
        }
        let toDelete = sorted.filter { !$0.isPinned }.suffix(from: maxCount)
        for item in toDelete {
            context.delete(item)
        }
    }
}
