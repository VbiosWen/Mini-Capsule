// Mini Capsule/UI/CapsuleCollapsedView.swift
import SwiftUI

struct CapsuleCollapsedView: View {
    let latestItem: ClipItem?
    let isCapturing: Bool
    let collapsedStyle: String

    @Environment(SettingsStore.self) var settings

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
            .shadow(
                color: .black.opacity(0.15),
                radius: 4,
                y: 2
            )
    }

    private var dotColor: Color {
        if settings.dotColorMode == "custom" {
            return Color(hex: settings.dotCustomColor) ?? .blue
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
            Rectangle()
                .fill(.ultraThinMaterial)
        }
        .clipShape(Capsule())
        .shadow(
            color: .black.opacity(0.15),
            radius: 8,
            y: 4
        )
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
