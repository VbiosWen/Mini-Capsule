// Mini Capsule/UI/ClipboardListViewModel.swift
import SwiftUI
import SwiftData
import AppKit

enum ContentFilter: String, CaseIterable {
    case all = "全部"
    case text = "文本"
    case image = "图片"
    case file = "文件"

    var systemImage: String {
        switch self {
        case .all: return "square.stack"
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
}

@MainActor
@Observable
final class ClipboardListViewModel {
    // MARK: - Filter State

    var searchText = ""
    var filterType: ContentFilter = .all

    // MARK: - Selection State

    var selectedItemIDs = Set<UUID>()
    var isMultiSelectMode = false
    var lastCopiedItemID: UUID?

    // MARK: - Dependencies

    let modelContext: ModelContext
    let settings: SettingsStore

    // MARK: - Init

    init(modelContext: ModelContext, settings: SettingsStore) {
        self.modelContext = modelContext
        self.settings = settings
    }

    // MARK: - Computed

    /// Fetch all items, sorted by pinned-first then timestamp descending.
    /// Pinned items sorted by sortOrder (ascending), unpinned by timestamp.
    var filteredItems: [ClipItem] {
        let descriptor = FetchDescriptor<ClipItem>(
            sortBy: [SortDescriptor(\ClipItem.timestamp, order: .reverse)]
        )
        let allItems = (try? modelContext.fetch(descriptor)) ?? []

        let typeFiltered: [ClipItem]
        switch filterType {
        case .all:
            typeFiltered = allItems
        case .text:
            typeFiltered = allItems.filter { $0.contentTypeRaw == "text" }
        case .image:
            typeFiltered = allItems.filter { $0.contentTypeRaw == "image" }
        case .file:
            typeFiltered = allItems.filter { $0.contentTypeRaw == "file" }
        }

        let searched: [ClipItem]
        if searchText.isEmpty {
            searched = typeFiltered
        } else {
            searched = typeFiltered.filter { item in
                item.textContent?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }

        // Pinned items first, sorted by sortOrder; unpinned by timestamp
        return searched.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            if a.isPinned {
                return (a.sortOrder ?? Int.max) < (b.sortOrder ?? Int.max)
            }
            return a.timestamp > b.timestamp
        }
    }

    var pinnedCount: Int {
        let descriptor = FetchDescriptor<ClipItem>(sortBy: [])
        let allItems = (try? modelContext.fetch(descriptor)) ?? []
        return allItems.filter(\.isPinned).count
    }

    var totalCount: Int {
        (try? modelContext.fetchCount(FetchDescriptor<ClipItem>())) ?? 0
    }

    // MARK: - Actions

    func copyItem(_ item: ClipItem) {
        PasteService.copyToClipboard(item)
        item.pasteCount += 1
        item.lastPastedAt = Date()
        item.timestamp = Date()
        try? modelContext.save()
        lastCopiedItemID = item.id
    }

    func pasteItem(_ item: ClipItem) {
        PasteService.paste(item, context: modelContext)
    }

    func deleteItem(_ item: ClipItem) {
        if let idx = selectedItemIDs.firstIndex(of: item.id) {
            selectedItemIDs.remove(at: idx)
        }
        modelContext.delete(item)
        try? modelContext.save()
    }

    func deleteSelected() {
        guard isMultiSelectMode, !selectedItemIDs.isEmpty else { return }
        let descriptor = FetchDescriptor<ClipItem>(sortBy: [])
        guard let items = try? modelContext.fetch(descriptor) else { return }
        for item in items where selectedItemIDs.contains(item.id) {
            modelContext.delete(item)
        }
        try? modelContext.save()
        selectedItemIDs.removeAll()
        isMultiSelectMode = false
    }

    func togglePin(_ item: ClipItem) {
        item.isPinned.toggle()
        if item.isPinned {
            // Assign next sort order
            let pinned = (try? modelContext.fetch(FetchDescriptor<ClipItem>(sortBy: [])))?.filter(\.isPinned) ?? []
            item.sortOrder = (pinned.map { $0.sortOrder ?? 0 }.max() ?? -1) + 1
        } else {
            item.sortOrder = nil
        }
        try? modelContext.save()
    }

    func editText(_ item: ClipItem, content: String) {
        item.textContent = content
        try? modelContext.save()
    }

    func toggleMultiSelect() {
        isMultiSelectMode.toggle()
        if !isMultiSelectMode {
            selectedItemIDs.removeAll()
        }
    }

    // MARK: - Keyboard Navigation

    func moveSelectionUp() {
        let items = filteredItems
        guard !items.isEmpty else { return }
        guard let currentID = selectedItemIDs.first,
              let idx = items.firstIndex(where: { $0.id == currentID }) else {
            selectedItemIDs = [items[0].id]
            return
        }
        let prev = max(idx - 1, 0)
        selectedItemIDs = [items[prev].id]
    }

    func moveSelectionDown() {
        let items = filteredItems
        guard !items.isEmpty else { return }
        guard let currentID = selectedItemIDs.first,
              let idx = items.firstIndex(where: { $0.id == currentID }) else {
            selectedItemIDs = [items[0].id]
            return
        }
        let next = min(idx + 1, items.count - 1)
        selectedItemIDs = [items[next].id]
    }

    func confirmSelection() {
        guard let selectedID = selectedItemIDs.first,
              let item = filteredItems.first(where: { $0.id == selectedID }) else { return }
        copyItem(item)
    }

    func handleEscape() {
        if !searchText.isEmpty {
            searchText = ""
        } else if isMultiSelectMode {
            toggleMultiSelect()
        }
        // collapse is handled by CapsuleViewModel — KeyboardEventHandler
        // calls this then CapsuleViewModel.collapse()
    }

    func selectAll() {
        selectedItemIDs = Set(filteredItems.map(\.id))
    }
}
