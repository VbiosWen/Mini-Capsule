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

    var body: some View {
        HStack(spacing: 10) {
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

            if isHovering && isInteractive {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(selectionBackground)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            guard isInteractive else { return }
            onTap()
        }
        .popover(isPresented: Binding(
            get: { isHovering && isInteractive && (item.contentTypeRaw == "image" || item.contentTypeRaw == "text") },
            set: { isHovering = $0 }
        ), arrowEdge: .trailing) {
            if item.contentTypeRaw == "image",
               let imageData = item.imageData,
               let nsImage = NSImage(data: imageData) {
                imagePreview(nsImage)
                    .padding(8)
            } else if item.contentTypeRaw == "text",
                      let text = item.textContent {
                textPreview(text)
                    .padding(8)
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

    // MARK: - Image Preview

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

    // MARK: - Text Preview

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

    // MARK: - Type Icon / Thumbnail

    @ViewBuilder
    private var typeIcon: some View {
        if item.contentTypeRaw == "image", let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
        } else {
            iconForType
                .font(.system(size: 15))
        }
    }

    private var iconForType: some View {
        switch item.contentTypeRaw {
        case "text":
            return Image(systemName: "doc.text")
        case "file":
            return Image(systemName: "doc")
        default:
            return Image(systemName: "questionmark")
        }
    }

    // MARK: - Preview Text

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
