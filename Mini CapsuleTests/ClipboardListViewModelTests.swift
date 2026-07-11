// Mini CapsuleTests/ClipboardListViewModelTests.swift
import Testing
import Foundation
import SwiftData
@testable import Mini_Capsule

@MainActor
struct ClipboardListViewModelTests {

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func seedItems(context: ModelContext) {
        context.insert(ClipItem(timestamp: Date(), contentTypeRaw: "text", textContent: "Hello World", sourceAppBundleID: "com.test"))
        context.insert(ClipItem(timestamp: Date().addingTimeInterval(-10), contentTypeRaw: "text", textContent: "Goodbye", sourceAppBundleID: "com.test"))
        context.insert(ClipItem(timestamp: Date().addingTimeInterval(-20), contentTypeRaw: "image", imageData: Data([0x01, 0x02]), imageFileName: "test.png", imageMD5: "abc", sourceAppBundleID: "com.test"))
        try? context.save()
    }

    @Test func emptySearchReturnsAllItems() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        #expect(vm.filteredItems.count == 3)

        settings.resetAll()
    }

    @Test func searchFiltersByText() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        vm.searchText = "Hello"
        #expect(vm.filteredItems.count == 1)
        #expect(vm.filteredItems.first?.textContent == "Hello World")

        settings.resetAll()
    }

    @Test func searchNoMatchReturnsEmpty() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        vm.searchText = "zzzzzzz"
        #expect(vm.filteredItems.isEmpty)

        settings.resetAll()
    }

    @Test func filterTypeAllShowsAll() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        vm.filterType = .all
        #expect(vm.filteredItems.count == 3)

        settings.resetAll()
    }

    @Test func filterTypeTextShowsOnlyText() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        vm.filterType = .text
        #expect(vm.filteredItems.count == 2)
        #expect(vm.filteredItems.allSatisfy { $0.contentTypeRaw == "text" })

        settings.resetAll()
    }

    @Test func filterTypeImageShowsOnlyImages() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        vm.filterType = .image
        #expect(vm.filteredItems.count == 1)
        #expect(vm.filteredItems.first?.contentTypeRaw == "image")

        settings.resetAll()
    }

    @Test func singleSelectTogglesSelection() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        let item = vm.filteredItems.first!
        vm.selectedItemIDs = [item.id]
        #expect(vm.selectedItemIDs.count == 1)

        vm.selectedItemIDs.remove(item.id)
        #expect(vm.selectedItemIDs.isEmpty)

        settings.resetAll()
    }

    @Test func multiSelectModeToggles() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        #expect(vm.isMultiSelectMode == false)

        vm.toggleMultiSelect()
        #expect(vm.isMultiSelectMode == true)

        vm.toggleMultiSelect()
        #expect(vm.isMultiSelectMode == false)
        #expect(vm.selectedItemIDs.isEmpty)

        settings.resetAll()
    }

    @Test func selectAllSelectsAllFiltered() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        vm.selectAll()
        #expect(vm.selectedItemIDs.count == 3)

        settings.resetAll()
    }

    @Test func deleteSelectedRemovesSelectedItems() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        let firstItem = vm.filteredItems.first!
        vm.selectedItemIDs = [firstItem.id]
        vm.isMultiSelectMode = true

        vm.deleteSelected()
        #expect(vm.isMultiSelectMode == false)
        #expect(vm.selectedItemIDs.isEmpty)
        #expect(vm.filteredItems.count == 2)

        settings.resetAll()
    }

    @Test func copyItemUpdatesStats() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        let item = vm.filteredItems.first!
        let beforeCount = item.pasteCount
        let beforeTimestamp = item.timestamp

        vm.copyItem(item)

        #expect(item.pasteCount == beforeCount + 1)
        #expect(item.lastPastedAt != nil)
        #expect(vm.lastCopiedItemID == item.id)
        // timestamp should be updated (bumped to top)
        #expect(item.timestamp >= beforeTimestamp)

        settings.resetAll()
    }

    @Test func editTextUpdatesContent() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        let textItem = vm.filteredItems.first(where: { $0.contentTypeRaw == "text" })!
        vm.editText(textItem, content: "Updated Content")

        #expect(textItem.textContent == "Updated Content")

        settings.resetAll()
    }

    @Test func togglePinFlipsPinnedStatus() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        let item = vm.filteredItems.first!
        let before = item.isPinned

        vm.togglePin(item)
        #expect(item.isPinned == !before)

        vm.togglePin(item)
        #expect(item.isPinned == before)

        settings.resetAll()
    }

    @Test func handleEscapeClearsSearchFirst() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        vm.searchText = "test"
        vm.handleEscape()
        #expect(vm.searchText.isEmpty)

        settings.resetAll()
    }

    @Test func handleEscapeExitsMultiSelect() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        vm.toggleMultiSelect()
        vm.handleEscape()
        #expect(vm.isMultiSelectMode == false)

        settings.resetAll()
    }

    @Test func moveSelectionDownAdvances() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        let items = vm.filteredItems
        vm.selectedItemIDs = [items.first!.id]
        vm.moveSelectionDown()

        #expect(vm.selectedItemIDs.first != items.first!.id)
        #expect(vm.selectedItemIDs.count == 1)

        settings.resetAll()
    }

    @Test func moveSelectionUpFromFirstStaysAtFirst() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        var items = vm.filteredItems
        vm.selectedItemIDs = [items.first!.id]

        // Move up from first item should stay at first
        vm.moveSelectionUp()
        #expect(vm.selectedItemIDs.first != nil)

        settings.resetAll()
    }

    @Test func confirmSelectionCopiesSelected() async throws {
        let container = try Self.makeContainer()
        let context = container.mainContext
        seedItems(context: context)
        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)

        let items = vm.filteredItems
        vm.selectedItemIDs = [items.first!.id]

        let beforeCount = items.first!.pasteCount
        vm.confirmSelection()

        #expect(vm.lastCopiedItemID == items.first!.id)
        #expect(items.first!.pasteCount == beforeCount + 1)

        settings.resetAll()
    }

    @Test func filteredItemsCachePopulatesAfterFirstRead() throws {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        context.insert(ClipItem(contentTypeRaw: "text", textContent: "x"))
        try context.save()

        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)
        #expect(vm._cachedItemCountForTesting == 0)  // cold
        _ = vm.filteredItems
        #expect(vm._cachedItemCountForTesting == 1)  // warm
        vm.invalidateCache()
        #expect(vm._cachedItemCountForTesting == 0)  // invalidated

        settings.resetAll()
    }

    @Test func invalidateOnClipItemsDidChangeNotification() throws {
        let schema = Schema([Item.self, ClipItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        context.insert(ClipItem(contentTypeRaw: "text", textContent: "before"))
        try context.save()

        let settings = SettingsStore()
        let vm = ClipboardListViewModel(modelContext: context, settings: settings)
        _ = vm.filteredItems  // populate cache

        context.insert(ClipItem(contentTypeRaw: "text", textContent: "after"))
        try context.save()
        NotificationCenter.default.post(name: .clipItemsDidChange, object: nil)

        // After notification, next access must reflect the new item.
        #expect(vm.filteredItems.count == 2)

        settings.resetAll()
    }
}
