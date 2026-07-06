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
    @State private var isExpandedReady = false

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
                    isExpandedReady: isExpandedReady,
                    onItemTap: { item in
                        PasteService.copyToClipboard(item)
                        item.pasteCount += 1
                        item.lastPastedAt = Date()
                        item.timestamp = Date()
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
                    isDragPrimed: isDragPrimed,
                    collapsedStyle: UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
                )
            }
        }
        .simultaneousGesture(windowDragGesture)
        .opacity(windowOpacity)
        .animation(.easeInOut(duration: 0.3), value: windowOpacity)
        .onHover { hovering in
            hoverWorkItem?.cancel()

            // Don't expand/collapse while a drag is in progress
            if dragWorkItem != nil || isDragPrimed || isDragging { return }

            if hovering {
                isExpandedReady = false
                let workItem = DispatchWorkItem {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded = true
                        searchText = ""
                    }
                    postExpandedNotification()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        isExpandedReady = true
                    }
                }
                hoverWorkItem = workItem
                let expandDelay = UserDefaults.standard.double(forKey: "hoverExpandDelay")
                let effectiveExpandDelay = expandDelay > 0 ? expandDelay : 0.3
                DispatchQueue.main.asyncAfter(deadline: .now() + effectiveExpandDelay, execute: workItem)
            } else {
                isExpandedReady = false
                let workItem = DispatchWorkItem {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isExpanded = false
                    }
                    postExpandedNotification()
                }
                hoverWorkItem = workItem
                let collapseDelay = UserDefaults.standard.double(forKey: "hoverCollapseDelay")
                let effectiveCollapseDelay = collapseDelay > 0 ? collapseDelay : 1.0
                DispatchQueue.main.asyncAfter(deadline: .now() + effectiveCollapseDelay, execute: workItem)
            }
        }
        .onChange(of: items.first?.id) { _, _ in
            isCapturing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isCapturing = false
            }
        }
    }

    private var windowOpacity: Double {
        let unfocusedOpacity = UserDefaults.standard.double(forKey: "panelOpacityUnfocused")
        let effectiveUnfocused = unfocusedOpacity > 0 ? unfocusedOpacity : 0.6
        // If expanded (hovering), fully opaque. Otherwise use unfocused setting.
        return isExpanded ? 1.0 : effectiveUnfocused
    }

    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Start 0.5s delay on first drag event
                if dragWorkItem == nil && !isDragPrimed && !isDragging {
                    // Cancel any pending hover expansion
                    hoverWorkItem?.cancel()
                    if isExpanded {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            isExpanded = false
                        }
                        postExpandedNotification()
                    }

                    let workItem = DispatchWorkItem {
                        isDragPrimed = true
                    }
                    dragWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
                }

                guard let panel = NSApp.windows.first(where: { $0 is CapsulePanel }) else { return }

                // Wait for drag to prime before moving
                if !isDragPrimed {
                    return
                }

                // Capture current translation as baseline on the first frame after priming
                if previousDragTranslation == nil {
                    previousDragTranslation = value.translation
                    return
                }

                // Incremental delta from previous frame — no jump
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
                    if let panel = NSApp.windows.first(where: { $0 is CapsulePanel }) {
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
