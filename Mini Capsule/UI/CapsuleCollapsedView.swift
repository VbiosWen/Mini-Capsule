// Mini Capsule/UI/CapsuleCollapsedView.swift
import SwiftUI
import AppKit

struct CapsuleCollapsedView: View {
    let latestItem: ClipItem?
    let isCapturing: Bool

    @State private var dragStartFrame: NSRect?

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
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard let panel = NSApp.windows.first(where: { $0 is NSPanel }) else { return }
                    if dragStartFrame == nil {
                        dragStartFrame = panel.frame
                    }
                    guard let startFrame = dragStartFrame else { return }
                    var newFrame = startFrame
                    newFrame.origin.x += value.translation.width
                    newFrame.origin.y -= value.translation.height
                    panel.setFrame(newFrame, display: true)
                }
                .onEnded { _ in
                    dragStartFrame = nil
                    // Save position after drag ends
                    if let panel = NSApp.windows.first(where: { $0 is NSPanel }) {
                        let frameDict: [String: CGFloat] = [
                            "x": panel.frame.origin.x,
                            "y": panel.frame.origin.y,
                            "w": panel.frame.size.width,
                            "h": panel.frame.size.height
                        ]
                        UserDefaults.standard.set(frameDict, forKey: "CapsuleWindowFrame")
                    }
                }
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
