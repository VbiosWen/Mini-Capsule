// Mini Capsule/UI/CapsuleExpandedView.swift
import SwiftUI
import SwiftData

struct CapsuleExpandedView: View {
    @Binding var searchText: String
    let isDragPrimed: Bool
    var onItemTap: (ClipItem) -> Void
    var onItemDelete: (ClipItem) -> Void

    @Query(
        sort: [SortDescriptor(\ClipItem.timestamp, order: .reverse)]
    ) private var allItems: [ClipItem]

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

                Button(action: {
                    if #available(macOS 14.0, *) {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } else {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                }) {
                    Image(systemName: "gear")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
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
                Rectangle()
                    .fill(.ultraThinMaterial)
                if isDragPrimed {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            if isDragPrimed {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.4), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        }
        .shadow(
            color: isDragPrimed ? .white.opacity(0.2) : .black.opacity(0.2),
            radius: isDragPrimed ? 8 : 12,
            y: isDragPrimed ? 3 : 6
        )
        .animation(.easeInOut(duration: 0.2), value: isDragPrimed)
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
