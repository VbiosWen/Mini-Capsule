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
    var imageFileName: String?
    var imageMD5: String?
    var fileBookmarks: Data?
    var isPinned: Bool
    var sortOrder: Int?  // non-nil for pinned items, nil for unpinned
    var sourceAppBundleID: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        lastPastedAt: Date? = nil,
        pasteCount: Int = 0,
        contentTypeRaw: String,
        textContent: String? = nil,
        imageData: Data? = nil,
        imageFileName: String? = nil,
        imageMD5: String? = nil,
        fileBookmarks: Data? = nil,
        isPinned: Bool = false,
        sortOrder: Int? = nil,    // non-nil for pinned items, nil for unpinned
        sourceAppBundleID: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.lastPastedAt = lastPastedAt
        self.pasteCount = pasteCount
        self.contentTypeRaw = contentTypeRaw
        self.textContent = textContent
        self.imageData = imageData
        self.imageFileName = imageFileName
        self.imageMD5 = imageMD5
        self.fileBookmarks = fileBookmarks
        self.isPinned = isPinned
        self.sortOrder = sortOrder
        self.sourceAppBundleID = sourceAppBundleID
    }
}
