// Mini Capsule/UI/CapsuleWindowController.swift
import AppKit
import SwiftUI
import SwiftData

/// Custom NSPanel that can become key when programmatically requested,
/// even with the nonactivatingPanel style — required for TextField input.
final class CapsulePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class CapsuleWindowController: NSWindowController, NSWindowDelegate {
    private let modelContainer: ModelContainer

    private static let frameKey = "CapsuleWindowFrame"
    private static let capsuleCollapsedSize = NSSize(width: 200, height: 36)
    private static let dotCollapsedSize = NSSize(width: 12, height: 12)
    private static let expandedSize = NSSize(width: 280, height: 360)

    private var currentCollapsedSize: NSSize {
        let style = UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
        return style == "dot" ? Self.dotCollapsedSize : Self.capsuleCollapsedSize
    }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer

        let savedFrame = Self.loadFrame()

        let panel = CapsulePanel(
            contentRect: savedFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: panel)

        if let window = self.window as? CapsulePanel {
            window.delegate = self
        }

        let capsuleView = CapsuleView()
            .modelContainer(modelContainer)

        panel.contentView = NSHostingView(rootView: capsuleView)
        panel.contentView?.wantsLayer = true

        observeExpandedState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindow() {
        window?.makeKeyAndOrderFront(nil)
    }

    func toggleWindow() {
        guard let window = window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func observeExpandedState() {
        NotificationCenter.default.addObserver(
            forName: .capsuleDidChangeExpanded,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let window = self.window,
                  let isExpanded = notification.userInfo?["isExpanded"] as? Bool else { return }

            let collapsedSize = self.currentCollapsedSize
            let targetSize = isExpanded ? Self.expandedSize : collapsedSize
            let currentFrame = window.frame

            let newFrame = NSRect(
                x: currentFrame.midX - targetSize.width / 2,
                y: currentFrame.maxY - targetSize.height,
                width: targetSize.width,
                height: targetSize.height
            )

            window.setFrame(newFrame, display: true, animate: true)

            // When expanded, make key so TextField can receive input
            if isExpanded {
                window.makeKey()
            }
        }

        // Listen for collapsed style changes
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, let window = self.window else { return }
            // If currently collapsed, resize to new collapsed size
            // (expanded state is managed by CapsuleView hover logic)
        }

        // Listen for show floating panel toggle
        NotificationCenter.default.addObserver(
            forName: .showFloatingPanelChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let window = self.window,
                  let show = notification.userInfo?["show"] as? Bool else { return }
            if show {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderOut(nil)
            }
        }
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    private func saveFrame() {
        guard let frame = window?.frame else { return }
        let frameDict: [String: CGFloat] = [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "w": frame.size.width,
            "h": frame.size.height
        ]
        UserDefaults.standard.set(frameDict, forKey: Self.frameKey)
    }

    private static func loadFrame() -> NSRect {
        let style = UserDefaults.standard.string(forKey: "collapsedStyle") ?? "capsule"
        let size = style == "dot" ? dotCollapsedSize : capsuleCollapsedSize

        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: size.width, height: size.height)
        }
        let screenWidth = screen.visibleFrame.width
        let screenHeight = screen.visibleFrame.maxY

        var x = (screenWidth - size.width) / 2
        var y = screenHeight - size.height - 40

        // Restore saved position, clamping to visible screen bounds
        if let dict = UserDefaults.standard.dictionary(forKey: frameKey) as? [String: CGFloat],
           let savedX = dict["x"], let savedY = dict["y"] {
            let screenFrame = screen.visibleFrame
            let clampedX = min(max(savedX, screenFrame.minX), screenFrame.maxX - size.width)
            let clampedY = min(max(savedY, screenFrame.minY), screenFrame.maxY - size.height)
            x = clampedX
            y = clampedY
        }

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}
