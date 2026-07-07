// Mini Capsule/UI/CapsuleView.swift
import SwiftUI
import SwiftData
import AppKit

extension NSNotification.Name {
    static let capsuleDidChangeExpanded = NSNotification.Name("capsuleDidChangeExpanded")
    static let capsuleDragStarted = NSNotification.Name("capsuleDragStarted")
    static let capsuleDragEnded = NSNotification.Name("capsuleDragEnded")
    static let resetCapsulePosition = NSNotification.Name("resetCapsulePosition")
}

struct CapsuleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipItem.timestamp, order: .reverse) private var items: [ClipItem]

    @State private var isExpanded = false
    @State private var isCapturing = false
    @State private var searchText = ""
    @State private var hoverWorkItem: DispatchWorkItem?
    @State private var isExpandedReady = false

    // Drag state — driven by CapsuleWindowController NSEvent monitor
    @State private var isDragging = false

    var body: some View {
        Group {
            if isExpanded {
                CapsuleExpandedView(
                    searchText: $searchText,
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
                    collapsedStyle: UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
                )
            }
        }
        .opacity(windowOpacity)
        .animation(.easeInOut(duration: 0.3), value: windowOpacity)
        .onHover { hovering in
            hoverWorkItem?.cancel()

            // Don't expand/collapse while a drag is in progress
            if isDragging { return }

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
        .onReceive(NotificationCenter.default.publisher(for: .capsuleDragStarted)) { _ in
            isDragging = true
            if isExpanded {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isExpanded = false
                }
                postExpandedNotification()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .capsuleDragEnded)) { _ in
            isDragging = false
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
