// Mini Capsule/UI/ClipItemRow.swift
import SwiftUI

struct ClipItemRow: View {
    let item: ClipItem
    let isSelected: Bool
    let isInteractive: Bool
    var isMultiSelectMode: Bool = false
    var onTap: () -> Void
    var onDelete: () -> Void

    @State private var isHovering = false
    @State private var showPopover = false
    @State private var showEditor = false
    @State private var isPopoverHovered = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 10) {
            // Multi-select checkbox
            if isMultiSelectMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.system(size: 16))
            }

            typeIcon
                .frame(width: 36, height: 36)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))

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

            if isHovering && isInteractive && !isMultiSelectMode {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(selectionBackground)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoverTask?.cancel()
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(200))  // U2: debounce
                    guard !Task.isCancelled else { return }
                    isHovering = true
                    showPopover = true
                }
            } else {
                hoverTask?.cancel()
                isHovering = false
                // Delay popover dismissal. If the mouse is currently hovering
                // the popover, don't dismiss — the popover's own hover exit will handle it.
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    if !isPopoverHovered {
                        showPopover = false
                    }
                }
            }
        }
        .onTapGesture {
            guard isInteractive else { return }
            onTap()
        }
        .contextMenu { contextMenuContent }  // E5
        .popover(isPresented: $showPopover, arrowEdge: .trailing) {
            popoverContent
                .onHover { hovering in
                    isPopoverHovered = hovering
                }
        }
        .onChange(of: isPopoverHovered) { _, hovering in
            if !hovering && showPopover {
                // Mouse left the popover — dismiss after a short grace period
                hoverTask?.cancel()
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    showPopover = false
                }
            }
        }
        .popover(isPresented: $showEditor, arrowEdge: .trailing) {
            PopoverEditorView(item: item) { newContent in
                // onSave is handled via the parent view model
                // We post a notification for the view model to pick up
                NotificationCenter.default.post(
                    name: .editTextItem,
                    object: nil,
                    userInfo: ["itemID": item.id, "content": newContent]
                )
            }
        }
    }

    // MARK: - Context Menu (E5)

    @ViewBuilder
    private var contextMenuContent: some View {
        Button("复制") { onTap() }
            .keyboardShortcut("c", modifiers: [])

        if item.contentTypeRaw == "text" {
            Button("粘贴到前台") {
                NotificationCenter.default.post(
                    name: .pasteItemToFront,
                    object: nil,
                    userInfo: ["itemID": item.id]
                )
            }
        }

        Divider()

        Button(item.isPinned ? "取消置顶" : "置顶") {
            NotificationCenter.default.post(
                name: .togglePinItem,
                object: nil,
                userInfo: ["itemID": item.id]
            )
        }

        if item.contentTypeRaw == "text" {
            Button("编辑") {
                showEditor = true
            }
        }

        Divider()

        Button("删除", role: .destructive) {
            onDelete()
        }
    }

    // MARK: - Popover Content

    @ViewBuilder
    private var popoverContent: some View {
        if item.contentTypeRaw == "image",
           let imageData = item.imageData,
           let nsImage = NSImage(data: imageData) {
            imagePreview(nsImage)
                .padding(8)
        } else if item.contentTypeRaw == "text",
                  let text = item.textContent {
            VStack(spacing: 0) {
                textPreview(text)
                    .padding(8)
                Divider()
                Button("编辑") {           // E4: Edit button in popover
                    showEditor = true
                    showPopover = false
                }
                .font(.system(size: 11))
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Selection

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.15))
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Previews

    @ViewBuilder
    private func imagePreview(_ nsImage: NSImage) -> some View {
        let imageSize = nsImage.size
        let maxWidth: CGFloat = 200
        let maxHeight: CGFloat = 300
        let scaleX = imageSize.width > maxWidth ? maxWidth / imageSize.width : 1.0
        let scaleY = imageSize.height > maxHeight ? maxHeight / imageSize.height : 1.0
        let scale = min(scaleX, scaleY)
        let displayWidth = imageSize.width * scale
        let displayHeight = imageSize.height * scale

        Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: displayWidth, height: displayHeight)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    @ViewBuilder
    private func textPreview(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 300, maxHeight: 200)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    // MARK: - Type Icon

    @ViewBuilder
    private var typeIcon: some View {
        if item.contentTypeRaw == "image", let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
        } else if item.contentTypeRaw == "text", let ch = firstDisplayCharacter(item.textContent) {
            Text(String(ch))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(Color.deterministic(from: item.id.uuidString))
                .frame(width: 36, height: 36)
        } else {
            iconForType
                .font(.system(size: 15))
        }
    }

    private func firstDisplayCharacter(_ text: String?) -> Character? {
        guard let text else { return nil }
        return text.first { !$0.isWhitespace && !$0.isNewline }
    }

    private var iconForType: some View {
        switch item.contentTypeRaw {
        case "text": return Image(systemName: "doc.text")
        case "file": return Image(systemName: "doc")
        default: return Image(systemName: "questionmark")
        }
    }

    private var previewText: String {
        switch item.contentTypeRaw {
        case "text":
            return item.textContent?.prefix(50).replacingOccurrences(of: "\n", with: " ") ?? ""
        case "image":
            return item.imageFileName ?? "图片"
        case "file":
            return "文件"
        default:
            return "未知"
        }
    }
}
