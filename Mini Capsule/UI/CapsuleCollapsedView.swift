// Mini Capsule/UI/CapsuleCollapsedView.swift
import SwiftUI

struct CapsuleCollapsedView: View {
    let latestItem: ClipItem?
    let isCapturing: Bool
    let isDragPrimed: Bool
    let collapsedStyle: String

    var body: some View {
        if collapsedStyle == "dot" {
            dotView
        } else {
            capsuleView
        }
    }

    // MARK: - Dot variant

    private var dotView: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 12, height: 12)
            .scaleEffect(isCapturing ? 1.3 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: isCapturing)
            .background {
                if isDragPrimed {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 18, height: 18)
                }
            }
            .shadow(
                color: isDragPrimed ? .white.opacity(0.3) : .black.opacity(0.15),
                radius: isDragPrimed ? 6 : 4,
                y: isDragPrimed ? 0 : 2
            )
            .animation(.easeInOut(duration: 0.2), value: isDragPrimed)
    }

    private var dotColor: Color {
        let mode = UserDefaults.standard.string(forKey: "dotColorMode") ?? "auto"
        if mode == "custom" {
            let hex = UserDefaults.standard.string(forKey: "dotCustomColor") ?? "#007AFF"
            return Color(hex: hex) ?? .blue
        }
        guard let item = latestItem else { return .gray }
        switch item.contentTypeRaw {
        case "text": return .green
        case "image": return .blue
        case "file": return .orange
        default: return .gray
        }
    }

    // MARK: - Capsule variant (existing)

    private var capsuleView: some View {
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
                Rectangle()
                    .fill(.ultraThinMaterial)
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
