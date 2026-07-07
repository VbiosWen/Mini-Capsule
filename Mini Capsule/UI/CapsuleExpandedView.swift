// Mini Capsule/UI/CapsuleExpandedView.swift
import SwiftUI
import SwiftData
import AppKit

struct CapsuleExpandedView: View {
    @Binding var searchText: String
    let isExpandedReady: Bool
    var onItemTap: (ClipItem) -> Void
    var onItemDelete: (ClipItem) -> Void

    @Query(
        sort: [SortDescriptor(\ClipItem.timestamp, order: .reverse)]
    ) private var allItems: [ClipItem]

    @FocusState private var isSearchFocused: Bool
    @State private var selectedItemID: UUID?
    @Environment(SettingsStore.self) var settings

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("搜索...", text: $searchText)
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
                    ForEach(filteredItems) { item in
                        ClipItemRow(
                            item: item,
                            isSelected: item.id == selectedItemID,
                            isInteractive: isExpandedReady,
                            onTap: { onItemTap(item) },
                            onDelete: { onItemDelete(item) }
                        )

                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }

            Divider()

            // Status bar
            HStack {
                if pinnedCount > 0 {
                    Text("📌 已置顶 \(pinnedCount) 条")
                        .font(.system(size: 11))
                }
                Spacer()
                Text("共 \(filteredItems.count) 条")
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
        .onChange(of: searchText) { _, _ in
            // Reset selection to first item when filter changes
            selectedItemID = filteredItems.first?.id
        }
        .onDisappear {
            selectedItemID = nil
        }
        .background(KeyboardMonitorView(
            filteredItems: filteredItems,
            selectedItemID: $selectedItemID,
            onSelect: { item in
                onItemTap(item)
            }
        ))
    }

    private var filteredItems: [ClipItem] {
        if searchText.isEmpty {
            return allItems
        }
        return allItems.filter { item in
            item.textContent?.localizedCaseInsensitiveContains(searchText) ?? false
        }
    }

    private var pinnedCount: Int {
        allItems.filter(\.isPinned).count
    }
}

// MARK: - Keyboard Monitor (NSViewRepresentable)

fileprivate struct KeyboardMonitorView: NSViewRepresentable {
    let filteredItems: [ClipItem]
    @Binding var selectedItemID: UUID?
    let onSelect: (ClipItem) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = MonitorView()
        view.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Return nil (consume) for handled keys; return event (pass through) for others
            return context.coordinator.handleKeyEvent(event) ? nil : event
        }
        context.coordinator.owner = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.filteredItems = filteredItems
        context.coordinator.onSelect = onSelect
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(filteredItems: filteredItems, selectedItemID: $selectedItemID, onSelect: onSelect)
    }

    final class Coordinator {
        var filteredItems: [ClipItem]
        var selectedItemID: Binding<UUID?>
        var onSelect: (ClipItem) -> Void
        weak var owner: MonitorView?

        init(filteredItems: [ClipItem], selectedItemID: Binding<UUID?>, onSelect: @escaping (ClipItem) -> Void) {
            self.filteredItems = filteredItems
            self.selectedItemID = selectedItemID
            self.onSelect = onSelect
        }

        func handleKeyEvent(_ event: NSEvent) -> Bool {
            guard !filteredItems.isEmpty else { return false }
            let currentIndex: Int
            if let id = selectedItemID.wrappedValue,
               let idx = filteredItems.firstIndex(where: { $0.id == id }) {
                currentIndex = idx
            } else {
                // No selection yet — start at -1 so first ↓ selects index 0
                currentIndex = -1
            }

            switch event.keyCode {
            case 125: // ↓ (down arrow)
                let next = min(currentIndex + 1, filteredItems.count - 1)
                selectedItemID.wrappedValue = filteredItems[next].id
                return true
            case 126: // ↑ (up arrow)
                let prev = max(currentIndex - 1, 0)
                selectedItemID.wrappedValue = filteredItems[prev].id
                return true
            case 36, 76: // Enter (36 = Return, 76 = numpad Enter)
                if let id = selectedItemID.wrappedValue,
                   let item = filteredItems.first(where: { $0.id == id }) {
                    onSelect(item)
                }
                return true
            default:
                // Pass through: character input reaches search field
                return false
            }
        }
    }

    final class MonitorView: NSView {
        var monitor: Any?

        deinit {
            if let m = monitor {
                NSEvent.removeMonitor(m)
            }
        }
    }
}
