// Mini Capsule/UI/ClipItemRow.swift
import SwiftUI

struct ClipItemRow: View {
    let item: ClipItem
    var onTap: () -> Void
    var onDelete: () -> Void

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
            onTap()
        }
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
