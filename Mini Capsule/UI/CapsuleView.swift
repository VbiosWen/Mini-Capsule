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

    // Long-press drag state
    @State private var isDragPrimed = false
    @State private var isDragging = false
    @State private var dragStartFrame: NSRect?
    @State private var dragWorkItem: DispatchWorkItem?
    @State private var previousDragTranslation: CGSize?

    var body: some View {
        Group {
            if isExpanded {
                CapsuleExpandedView(
                    searchText: $searchText,
                    isDragPrimed: isDragPrimed,
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
                    isCapturing: isCapturing,
                    isDragPrimed: isDragPrimed
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
        .onChange(of: items.first?.id) { _, _ in
            isCapturing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isCapturing = false
            }
        }
    }

    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Start 0.5s delay on first drag event
                if dragWorkItem == nil && !isDragPrimed && !isDragging {
                    let workItem = DispatchWorkItem {
                        isDragPrimed = true
                    }
                    dragWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
                }

                guard let panel = NSApp.windows.first(where: { $0 is NSPanel }) else { return }

                // Capture frame and reset delta tracking before drag actually moves the window
                if !isDragPrimed {
                    if dragStartFrame == nil {
                        dragStartFrame = panel.frame
                        previousDragTranslation = .zero
                    }
                    return
                }

                // Use incremental delta from current window position
                let prev = previousDragTranslation ?? .zero
                let deltaX = value.translation.width - prev.width
                let deltaY = value.translation.height - prev.height
                var newFrame = panel.frame
                newFrame.origin.x += deltaX
                newFrame.origin.y -= deltaY
                panel.setFrame(newFrame, display: true)
                previousDragTranslation = value.translation
                isDragging = true
            }
            .onEnded { _ in
                dragWorkItem?.cancel()
                dragWorkItem = nil

                if isDragging {
                    if let panel = NSApp.windows.first(where: { $0 is NSPanel }) {
                        UserDefaults.standard.set([
                            "x": panel.frame.origin.x,
                            "y": panel.frame.origin.y,
                            "w": panel.frame.size.width,
                            "h": panel.frame.size.height
                        ], forKey: "CapsuleWindowFrame")
                    }
                }

                isDragPrimed = false
                isDragging = false
                dragStartFrame = nil
                previousDragTranslation = nil
            }
    }

    private func postExpandedNotification() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(
                name: .capsuleDidChangeExpanded,
                object: nil,
                userInfo: ["isExpanded": isExpanded]
            )
        }
    }
}
