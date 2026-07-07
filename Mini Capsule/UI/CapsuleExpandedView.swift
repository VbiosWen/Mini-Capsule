// Mini Capsule/UI/CapsuleExpandedView.swift
import SwiftUI
import SwiftData
import AppKit

struct CapsuleExpandedView: View {
    @Bindable var viewModel: ClipboardListViewModel
    var capsuleViewModel: CapsuleViewModel

    @FocusState private var isSearchFocused: Bool
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Search bar
                searchBar

                Divider()

                // Filter tabs
                filterTabs

                Divider()

                // Item list
                itemList

                Divider()

                // Bottom bar
                bottomBar
            }
            .frame(width: 280, height: 360)
            .background {
                backgroundLayer
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
            .onAppear {
                isSearchFocused = true
                if let first = viewModel.filteredItems.first {
                    viewModel.selectedItemIDs = [first.id]
                }
            }
            .onDisappear {
                viewModel.selectedItemIDs.removeAll()
                viewModel.isMultiSelectMode = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .capsuleEscapePressed)) { _ in
                // If search is empty and not in multi-select mode, collapse
                if viewModel.searchText.isEmpty && !viewModel.isMultiSelectMode {
                    capsuleViewModel.collapse()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .capsuleEditTextItem)) { notification in
                guard let userInfo = notification.userInfo,
                      let item = userInfo["item"] as? ClipItem,
                      let content = userInfo["content"] as? String else { return }
                viewModel.editText(item, content: content)
            }
            .onReceive(NotificationCenter.default.publisher(for: .capsulePasteItemToFront)) { notification in
                guard let userInfo = notification.userInfo,
                      let item = userInfo["item"] as? ClipItem else { return }
                viewModel.pasteItem(item)
            }
            .onReceive(NotificationCenter.default.publisher(for: .capsuleTogglePinItem)) { notification in
                guard let userInfo = notification.userInfo,
                      let item = userInfo["item"] as? ClipItem else { return }
                viewModel.togglePin(item)
            }
            .background(
                KeyboardEventHandler(viewModel: viewModel)
            )

            // Copy feedback overlay
            VStack {
                Spacer()
                CopyFeedbackView(viewModel: viewModel)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            TextField("搜索...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFocused)

            if #available(macOS 14.0, *) {
                SettingsLink {
                    Image(systemName: "gear")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }) {
                    Image(systemName: "gear")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Filter Tabs (U4)

    private var filterTabs: some View {
        HStack(spacing: 8) {
            ForEach(ContentFilter.allCases, id: \.rawValue) { filter in
                filterTab(filter)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func filterTab(_ filter: ContentFilter) -> some View {
        Button(action: { viewModel.filterType = filter }) {
            HStack(spacing: 4) {
                Image(systemName: filter.systemImage)
                    .font(.system(size: 10))
                Text(filter.rawValue)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                viewModel.filterType == filter
                    ? Color.accentColor.opacity(0.2)
                    : Color.clear
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Item List

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filteredItems) { item in
                    ClipItemRow(
                        item: item,
                        isSelected: viewModel.selectedItemIDs.contains(item.id),
                        isInteractive: capsuleViewModel.isExpandingReady,
                        isMultiSelectMode: viewModel.isMultiSelectMode,
                        onTap: {
                            if viewModel.isMultiSelectMode {
                                if viewModel.selectedItemIDs.contains(item.id) {
                                    viewModel.selectedItemIDs.remove(item.id)
                                } else {
                                    viewModel.selectedItemIDs.insert(item.id)
                                }
                            } else {
                                viewModel.copyItem(item)
                            }
                        },
                        onDelete: { viewModel.deleteItem(item) }
                    )

                    Divider()
                        .padding(.leading, 12)
                }
            }
        }
    }

    // MARK: - Bottom Bar (U5 batch delete)

    private var bottomBar: some View {
        HStack {
            if viewModel.isMultiSelectMode {
                Button(action: { viewModel.deleteSelected() }) {
                    Text("删除所选 (\(viewModel.selectedItemIDs.count))")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.selectedItemIDs.isEmpty)

                Spacer()

                Button("取消") {
                    viewModel.toggleMultiSelect()
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
            } else {
                if viewModel.pinnedCount > 0 {
                    Text("📌 已置顶 \(viewModel.pinnedCount) 条")
                        .font(.system(size: 11))
                }
                Spacer()
                Text("共 \(viewModel.filteredItems.count) 条")
                    .font(.system(size: 11))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundColor(.secondary)
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            if !settings.backgroundImageData.isEmpty,
               let nsImage = NSImage(data: settings.backgroundImageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            Rectangle()
                .fill(.ultraThinMaterial)
        }
    }
}
