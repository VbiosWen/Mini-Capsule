// Mini Capsule/UI/CapsuleView.swift
import SwiftUI
import SwiftData
import AppKit

extension NSNotification.Name {
    static let capsuleDidChangeExpanded = NSNotification.Name("capsuleDidChangeExpanded")
}

struct CapsuleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipItem.timestamp, order: .reverse) private var items: [ClipItem]

    @State private var isExpanded = false
    @State private var isCapturing = false
    @State private var searchText = ""
    @State private var hoverWorkItem: DispatchWorkItem?
    @State private var dragStartFrame: NSRect?

    var body: some View {
        Group {
            if isExpanded {
                CapsuleExpandedView(
                    searchText: $searchText,
                    onItemTap: { item in
                        PasteService.copyToClipboard(item)
                        item.pasteCount += 1
                        item.lastPastedAt = Date()
                        try? modelContext.save()
                    },
                    onItemDelete: { item in
                        withAnimation {
                            modelContext.delete(item)
                            try? modelContext.save()
                        }
                    }
                )
            } else {
                CapsuleCollapsedView(
                    latestItem: items.first,
                    isCapturing: isCapturing
                )
            }
        }
        .simultaneousGesture(windowDragGesture)
        .onHover { hovering in
            hoverWorkItem?.cancel()

            if hovering {
                let workItem = DispatchWorkItem {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded = true
                        searchText = ""
                    }
                    postExpandedNotification()
                }
                hoverWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
            } else {
                let workItem = DispatchWorkItem {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isExpanded = false
                    }
                    postExpandedNotification()
                }
                hoverWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
            }
        }
        // Flash animation when new item captured
        .onChange(of: items.first?.id) { _, _ in
            isCapturing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isCapturing = false
            }
        }
    }

    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
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
                if let panel = NSApp.windows.first(where: { $0 is NSPanel }) {
                    UserDefaults.standard.set([
                        "x": panel.frame.origin.x,
                        "y": panel.frame.origin.y,
                        "w": panel.frame.size.width,
                        "h": panel.frame.size.height
                    ], forKey: "CapsuleWindowFrame")
                }
            }
    }

    private func postExpandedNotification() {
        // Short delay to let animation start, then notify window to resize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(
                name: .capsuleDidChangeExpanded,
                object: nil,
                userInfo: ["isExpanded": isExpanded]
            )
        }
    }
}
