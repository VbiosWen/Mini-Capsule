// Mini Capsule/Services/FrequencyCleanupService.swift
import Foundation
import SwiftData

enum FrequencyCleanupService {
    static func performCleanup(context: ModelContext, keepCount: Int? = nil, settings: SettingsProtocol? = nil) {
        let allItems = FetchDescriptor<ClipItem>()

        guard let items = try? context.fetch(allItems) else { return }

        let keep = keepCount ?? max(settings?.historyMaxCount ?? 200, 1)

        let sorted = items.sorted { a, b in
            if a.isPinned != b.isPinned {
                return a.isPinned
            }
            return a.pasteCount > b.pasteCount
        }

        var kept = 0

        let toDelete = sorted.filter { item in
            if item.isPinned {
                return false
            }
            kept += 1
            return kept > keep
        }

        for item in toDelete {
            context.delete(item)
        }

        try? context.save()
    }
}
