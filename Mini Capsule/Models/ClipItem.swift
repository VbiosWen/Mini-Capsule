// Mini Capsule/Models/ClipItem.swift
import Foundation
import SwiftData

@Model
final class ClipItem {
    var id: UUID
    var timestamp: Date
    var lastPastedAt: Date?
    var pasteCount: Int
    var contentTypeRaw: String
    var textContent: String?
    var imageData: Data?
    var fileBookmarks: Data?
    var isPinned: Bool
    var sourceAppBundleID: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        lastPastedAt: Date? = nil,
        pasteCount: Int = 0,
        contentTypeRaw: String,
        textContent: String? = nil,
        imageData: Data? = nil,
        fileBookmarks: Data? = nil,
        isPinned: Bool = false,
        sourceAppBundleID: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.lastPastedAt = lastPastedAt
        self.pasteCount = pasteCount
        self.contentTypeRaw = contentTypeRaw
        self.textContent = textContent
        self.imageData = imageData
        self.fileBookmarks = fileBookmarks
        self.isPinned = isPinned
        self.sourceAppBundleID = sourceAppBundleID
    }
}
