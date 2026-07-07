// Mini Capsule/UI/KeyboardEventHandler.swift
import SwiftUI
import AppKit

/// Independent NSViewRepresentable that bridges NSEvent keyDown to
/// ClipboardListViewModel keyboard navigation methods.
/// Replaces the fileprivate KeyboardMonitorView previously embedded
/// in CapsuleExpandedView.swift.
struct KeyboardEventHandler: NSViewRepresentable {
    typealias NSViewType = MonitorView

    let viewModel: ClipboardListViewModel

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            return context.coordinator.handleKeyEvent(event) ? nil : event
        }
        context.coordinator.owner = view
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        // ViewModel is observed via @Observable — no manual update needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    final class Coordinator {
        private weak var viewModel: ClipboardListViewModel?
        weak var owner: MonitorView?

        init(viewModel: ClipboardListViewModel) {
            self.viewModel = viewModel
        }

        func handleKeyEvent(_ event: NSEvent) -> Bool {
            guard let vm = viewModel, !vm.filteredItems.isEmpty else { return false }

            // Don't intercept keys when a text input view is focused (search bar, popover editor, etc.)
            if let fr = NSApp.keyWindow?.firstResponder as? NSView {
                if fr is NSTextView || fr is NSTextField {
                    return false
                }
            }

            // Check for Cmd+A first (select all)
            if event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers?.lowercased(),
               chars == "a" {
                vm.selectAll()
                return true
            }

            switch event.keyCode {
            case 125: // ↓
                vm.moveSelectionDown()
                return true
            case 126: // ↑
                vm.moveSelectionUp()
                return true
            case 36, 76: // Return, numpad Enter
                vm.confirmSelection()
                return true
            case 53: // Escape
                vm.handleEscape()
                // Also signal CapsuleViewModel to collapse if needed
                NotificationCenter.default.post(
                    name: .capsuleEscapePressed,
                    object: nil
                )
                return true
            default:
                return false // pass through to search field
            }
        }
    }

    final class MonitorView: NSView {
        var monitor: Any?

        deinit {
            if let m = monitor {
                NSEvent.removeMonitor(m)
            }
        }
    }
}
