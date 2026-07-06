// Mini Capsule/UI/CapsuleCollapsedView.swift
import SwiftUI

struct CapsuleCollapsedView: View {
    let latestItem: ClipItem?
    let isCapturing: Bool
    let isDragPrimed: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isCapturing ? Color.blue : Color.green)
                .frame(width: 8, height: 8)
                .scaleEffect(isCapturing ? 1.3 : 1.0)
                .animation(.easeInOut(duration: 0.3), value: isCapturing)

            Text(summaryText)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(width: 200, height: 36)
        .background {
            ZStack {
                // Base material
                Rectangle()
                    .fill(.ultraThinMaterial)

                // Drag-primed glow overlay
                if isDragPrimed {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                }
            }
        }
        .clipShape(Capsule())
        .shadow(
            color: isDragPrimed ? .white.opacity(0.3) : .black.opacity(0.15),
            radius: isDragPrimed ? 6 : 8,
            y: isDragPrimed ? 0 : 4
        )
        .animation(.easeInOut(duration: 0.2), value: isDragPrimed)
    }

    private var summaryText: String {
        guard let item = latestItem else { return "等待复制..." }
        switch item.contentTypeRaw {
        case "text":
            return item.textContent?.prefix(20).replacingOccurrences(of: "\n", with: " ") ?? ""
        case "image":
            return "🖼️ 图片"
        case "file":
            return "📁 文件"
        default:
            return ""
        }
    }
}
