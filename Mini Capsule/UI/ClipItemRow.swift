// Mini Capsule/UI/ClipItemRow.swift
import SwiftUI

struct ClipItemRow: View {
    let item: ClipItem
    var onTap: () -> Void
    var onDelete: () -> Void
    let isPreviewing: Bool
    var onTogglePreview: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            typeIcon
                .frame(width: 28, height: 28)
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

            if isHovering {
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
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            if item.contentTypeRaw == "image" {
                onTogglePreview?()
            } else {
                onTap()
            }
        }
        .overlay {
            if isPreviewing, let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
                HStack {
                    Spacer()
                    imagePreview(nsImage)
                        .offset(x: 280 + 8, y: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func imagePreview(_ nsImage: NSImage) -> some View {
        let imageSize = nsImage.size
        let maxWidth: CGFloat = 200
        let maxHeight: CGFloat = 300

        // Calculate display size: min(original, max), preserving aspect ratio
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

    private var typeIcon: some View {
        switch item.contentTypeRaw {
        case "text":
            return Image(systemName: "doc.text")
                .font(.system(size: 13))
        case "image":
            return Image(systemName: "photo")
                .font(.system(size: 13))
        case "file":
            return Image(systemName: "doc")
                .font(.system(size: 13))
        default:
            return Image(systemName: "questionmark")
                .font(.system(size: 13))
        }
    }

    private var previewText: String {
        switch item.contentTypeRaw {
        case "text":
            return item.textContent?.prefix(50).replacingOccurrences(of: "\n", with: " ") ?? ""
        case "image":
            return "图片"
        case "file":
            return "文件"
        default:
            return "未知"
        }
    }
}
