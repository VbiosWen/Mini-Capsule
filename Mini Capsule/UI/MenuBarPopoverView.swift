// Mini Capsule/UI/MenuBarPopoverView.swift
import SwiftUI

/// NSPopover content for the menu bar status item.
/// Shows a scrollable list of recent clipboard items plus bottom action buttons.
struct MenuBarPopoverView: View {
    let items: [ClipItem]
    let showFloatingPanel: Bool
    var onSelect: (ClipItem) -> Void
    var onToggleFloating: () -> Void
    var onSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            MenuBarItemRow(item: item)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(item) }

                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }

            Divider()

            // Bottom actions
            VStack(spacing: 0) {
                actionButton(
                    label: showFloatingPanel ? "隐藏悬浮窗" : "打开悬浮窗",
                    systemImage: showFloatingPanel ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle",
                    action: onToggleFloating
                )

                if #available(macOS 14.0, *) {
                    SettingsLink {
                        HStack(spacing: 8) {
                            Image(systemName: "gear")
                                .font(.system(size: 12))
                                .frame(width: 20)
                                .foregroundColor(.secondary)
                            Text("设置...")
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                            Spacer()
                            Text("⌘,")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                } else {
                    actionButton(
                        label: "设置...",
                        systemImage: "gear",
                        shortcut: "⌘,",
                        action: onSettings
                    )
                }

                Divider()
                    .padding(.leading, 12)

                actionButton(
                    label: "退出 Mini Capsule",
                    systemImage: "xmark.square",
                    action: onQuit
                )
            }
        }
        .frame(width: 300)
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "clipboard")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("暂无剪贴板记录")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(height: 120)
    }

    // MARK: - Action Button

    /// Action row that uses `.onTapGesture` instead of `Button`.
    /// SwiftUI `Button` events are not reliably delivered inside an `NSPopover`
    /// backed by `NSHostingController` — the popover's event handling can
    /// intercept them. Using `.onTapGesture` matches the pattern on item rows,
    /// which work correctly.
    private func actionButton(label: String, systemImage: String, shortcut: String? = nil, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .frame(width: 20)
                .foregroundColor(.secondary)

            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.primary)

            Spacer()

            if let shortcut = shortcut {
                Text(shortcut)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { action() }
    }
}

// MARK: - Item Row

private struct MenuBarItemRow: View {
    let item: ClipItem

    var body: some View {
        HStack(spacing: 10) {
            typeIcon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(previewText)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(item.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    // MARK: - Type Icon

    @ViewBuilder
    private var typeIcon: some View {
        if item.contentTypeRaw == "image",
           let thumbData = item.imageThumbnail ?? item.imageData,
           let nsImage = NSImage(data: thumbData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else if item.contentTypeRaw == "text", let ch = item.textContent?.first(where: { !$0.isWhitespace && !$0.isNewline }) {
            Text(String(ch))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(Color.deterministic(from: item.id.uuidString))
                .frame(width: 28, height: 28)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: iconName)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private var iconName: String {
        switch item.contentTypeRaw {
        case "text": return "doc.text"
        case "image": return "photo"
        case "file": return "doc"
        default: return "clipboard"
        }
    }

    // MARK: - Preview Text

    private var previewText: String {
        switch item.contentTypeRaw {
        case "text":
            return item.textContent?
                .prefix(40)
                .replacingOccurrences(of: "\n", with: " ") ?? ""
        case "image":
            return item.imageFileName ?? "图片"
        case "file":
            return item.imageFileName ?? "文件"
        default:
            return "未知"
        }
    }
}

#if DEBUG
#Preview {
    MenuBarPopoverView(
        items: [],
        showFloatingPanel: true,
        onSelect: { _ in },
        onToggleFloating: {},
        onSettings: {},
        onQuit: {}
    )
    .frame(height: 200)
}
#endif
