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
    // MARK: - Filter State (observed)

    var searchText = ""
    var filterType: ContentFilter = .all

    // MARK: - Selection State (observed)

    var selectedItemIDs = Set<UUID>()
    var isMultiSelectMode = false
    var lastCopiedItemID: UUID?

    // MARK: - Cache Version (observed)
    /// Tracked so SwiftUI re-renders when we invalidate. Consumers read
    /// `filteredItems` which reads this transitively.
    private var cacheVersion: Int = 0

    // MARK: - Dependencies

    let modelContext: ModelContext
    let settings: SettingsStore

    // MARK: - Cache Storage (not observed)

    @ObservationIgnored private var itemsCache: [ClipItem] = []
    @ObservationIgnored private var cacheKey: CacheKey?
    @ObservationIgnored private var changeObserver: NSObjectProtocol?

    private struct CacheKey: Equatable {
        let search: String
        let filter: ContentFilter
        let version: Int
    }

    // MARK: - Init / Deinit

    init(modelContext: ModelContext, settings: SettingsStore) {
        self.modelContext = modelContext
        self.settings = settings
        self.changeObserver = NotificationCenter.default.addObserver(
            forName: .clipItemsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.invalidateCache()
        }
    }

    deinit {
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Cache Control

    func invalidateCache() {
        cacheVersion &+= 1
        cacheKey = nil
        itemsCache = []
    }

    /// Clear the strong ref array without bumping version. Called on capsule
    /// collapse so SwiftData can release the managed objects.
    func purgeCache() {
        cacheKey = nil
        itemsCache = []
    }

    /// Testing SPI — how many ClipItems the cache currently retains.
    var _cachedItemCountForTesting: Int { itemsCache.count }

    // MARK: - Computed

    /// Fetch all items, sorted by pinned-first then timestamp descending.
    /// Pinned items sorted by sortOrder (ascending), unpinned by timestamp.
    /// Memoized on (searchText, filterType, cacheVersion).
    var filteredItems: [ClipItem] {
        let key = CacheKey(search: searchText, filter: filterType, version: cacheVersion)
        if key == cacheKey { return itemsCache }

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

        let result = searched.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            if a.isPinned {
                return (a.sortOrder ?? Int.max) < (b.sortOrder ?? Int.max)
            }
            return a.timestamp > b.timestamp
        }
        cacheKey = key
        itemsCache = result
        return result
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
        invalidateCache()
    }

    func pasteItem(_ item: ClipItem) {
        PasteService.paste(item, context: modelContext)
        invalidateCache()
    }

    func deleteItem(_ item: ClipItem) {
        if let idx = selectedItemIDs.firstIndex(of: item.id) {
            selectedItemIDs.remove(at: idx)
        }
        modelContext.delete(item)
        try? modelContext.save()
        invalidateCache()
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
        invalidateCache()
    }

    func togglePin(_ item: ClipItem) {
        item.isPinned.toggle()
        if item.isPinned {
            let pinned = (try? modelContext.fetch(FetchDescriptor<ClipItem>(sortBy: [])))?.filter(\.isPinned) ?? []
            item.sortOrder = (pinned.map { $0.sortOrder ?? 0 }.max() ?? -1) + 1
        } else {
            item.sortOrder = nil
        }
        try? modelContext.save()
        invalidateCache()
    }

    func editText(_ item: ClipItem, content: String) {
        item.textContent = content
        try? modelContext.save()
        invalidateCache()
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
    }

    func selectAll() {
        selectedItemIDs = Set(filteredItems.map(\.id))
    }
}
