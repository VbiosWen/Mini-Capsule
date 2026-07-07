// Mini Capsule/UI/CapsuleView.swift
import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct CapsuleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipItem.timestamp, order: .reverse) private var items: [ClipItem]

    @State private var capsuleVM: CapsuleViewModel
    @State private var listVM: ClipboardListViewModel
    @Environment(SettingsStore.self) private var settings

    init(modelContext: ModelContext, settings: SettingsStore) {
        let capsuleVM = CapsuleViewModel(settings: settings)
        let listVM = ClipboardListViewModel(modelContext: modelContext, settings: settings)
        _capsuleVM = State(initialValue: capsuleVM)
        _listVM = State(initialValue: listVM)
    }

    var body: some View {
        Group {
            if capsuleVM.isExpanded {
                CapsuleExpandedView(viewModel: listVM, capsuleViewModel: capsuleVM)
            } else {
                CapsuleCollapsedView(
                    latestItem: items.first,
                    isCapturing: capsuleVM.isCapturing,
                    collapsedStyle: settings.collapsedStyle
                )
            }
        }
        .opacity(capsuleVM.windowOpacity)
        .animation(.easeInOut(duration: 0.3), value: capsuleVM.windowOpacity)
        .onHover { hovering in
            if hovering {
                // Don't expand while mouse button is pressed — that's a drag intent
                if NSEvent.pressedMouseButtons == 0 {
                    capsuleVM.onHoverEnter()
                }
            } else {
                // Don't collapse while user is interacting with the capsule panel
                if capsuleVM.isExpanded, NSApp.keyWindow is CapsulePanel { return }
                capsuleVM.onHoverExit()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .capsuleDragStarted)) { _ in
            capsuleVM.onDragStart()
        }
        .onReceive(NotificationCenter.default.publisher(for: .capsuleDragEnded)) { _ in
            capsuleVM.onDragEnd()
        }
        .onReceive(NotificationCenter.default.publisher(for: .capsuleDidResignKey)) { _ in
            capsuleVM.collapse()
        }
        .onChange(of: items.first?.id) { _, _ in
            capsuleVM.onNewItemCaptured()
        }
    }
}
