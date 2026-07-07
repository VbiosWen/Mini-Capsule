// Mini Capsule/UI/CapsuleCollapsedView.swift
import SwiftUI

struct CapsuleCollapsedView: View {
    let latestItem: ClipItem?
    let isCapturing: Bool
    let collapsedStyle: String

    @Environment(SettingsStore.self) var settings

    var body: some View {
        switch collapsedStyle {
        case "dot":
            ringView
        case "icon":
            iconView
        default:
            capsuleView
        }
    }

    // MARK: - Ring variant (rainbow)

    private var ringView: some View {
        Circle()
            .stroke(
                AngularGradient(
                    colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                    center: .center
                ),
                lineWidth: settings.ringDiameter * 0.20
            )
            .frame(width: settings.ringDiameter, height: settings.ringDiameter)
            .scaleEffect(isCapturing ? 1.3 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isCapturing)
            .shadow(
                color: .black.opacity(0.15),
                radius: 4,
                y: 2
            )
    }

    // MARK: - Icon variant (E2)

    private var iconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.ultraThinMaterial)
                .frame(width: 24, height: 24)

            Image(systemName: typeIconName)
                .font(.system(size: 14))
                .foregroundColor(.primary)
        }
        .scaleEffect(isCapturing ? 1.2 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isCapturing)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private var typeIconName: String {
        guard let item = latestItem else { return "clipboard" }
        switch item.contentTypeRaw {
        case "text": return "doc.text"
        case "image": return "photo"
        case "file": return "doc"
        default: return "clipboard"
        }
    }

    // MARK: - Capsule variant (existing)

    private var capsuleView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isCapturing ? Color.blue : Color.green)
                .frame(width: 8, height: 8)
                .scaleEffect(isCapturing ? 1.3 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isCapturing)

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
