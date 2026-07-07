// Mini Capsule/UI/CapsuleExpandedView.swift
import SwiftUI
import SwiftData
import AppKit

struct CapsuleExpandedView: View {
    let viewModel: ClipboardListViewModel
    let capsuleViewModel: CapsuleViewModel

    @FocusState private var isSearchFocused: Bool
    @Environment(SettingsStore.self) var settings

    var body: some View {
        @Bindable var vm = viewModel

        return VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("搜索...", text: $vm.searchText)
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

            Divider()

            // Item list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.filteredItems) { item in
                        ClipItemRow(
                            item: item,
                            isSelected: viewModel.selectedItemIDs.contains(item.id),
                            isInteractive: capsuleViewModel.isExpandingReady,
                            onTap: { viewModel.copyItem(item) },
                            onDelete: { viewModel.deleteItem(item) }
                        )

                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }

            Divider()

            // Status bar
            HStack {
                if viewModel.pinnedCount > 0 {
                    Text("📌 已置顶 \(viewModel.pinnedCount) 条")
                        .font(.system(size: 11))
                }
                Spacer()
                Text("共 \(viewModel.filteredItems.count) 条")
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(.secondary)
        }
        .frame(width: 280, height: 360)
        .background {
            ZStack {
                // Background image (if set)
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(
            color: .black.opacity(0.2),
            radius: 12,
            y: 6
        )
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: viewModel.searchText) { _, _ in
            // Reset selection to first item when filter changes
            if let first = viewModel.filteredItems.first {
                viewModel.selectedItemIDs = [first.id]
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .capsuleEscapePressed)) { _ in
            capsuleViewModel.collapse()
        }
        .background(KeyboardEventHandler(viewModel: viewModel))
    }
}
