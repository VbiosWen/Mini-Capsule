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
    private let settingsStore: SettingsStore
    private var isExpanded = false
    private var observers: [NSObjectProtocol] = []

    // Drag monitoring
    private var dragMonitor: Any?
    private var dragPrimer: DispatchWorkItem?
    private var isDragActive = false
    private var previousDragLocation: NSPoint?

    private static let capsuleCollapsedSize = NSSize(width: 200, height: 36)
    private static let dotCollapsedSize = NSSize(width: 12, height: 12)
    private static let expandedSize = NSSize(width: 280, height: 360)

    private var currentCollapsedSize: NSSize {
        return settingsStore.collapsedStyle == "dot" ? Self.dotCollapsedSize : Self.capsuleCollapsedSize
    }

    init(modelContainer: ModelContainer, settingsStore: SettingsStore) {
        self.modelContainer = modelContainer
        self.settingsStore = settingsStore

        let savedFrame = Self.loadFrame(style: settingsStore.collapsedStyle)

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
        panel.isMovableByWindowBackground = false
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
            .environment(settingsStore)
            .modelContainer(modelContainer)

        panel.contentView = NSHostingView(rootView: capsuleView)
        panel.contentView?.wantsLayer = true
        // Clip window to capsule shape
        panel.contentView?.layer?.masksToBounds = true
        panel.contentView?.layer?.cornerRadius = settingsStore.collapsedStyle == "dot" ? 6 : 18

        observeExpandedState()
        startDragMonitoring()
    }

    deinit {
        dragPrimer?.cancel()
        if let monitor = dragMonitor {
            NSEvent.removeMonitor(monitor)
        }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
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

    private func startDragMonitoring() {
        dragMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self = self, event.window == self.window else { return event }

            switch event.type {
            case .leftMouseDown:
                self.previousDragLocation = event.locationInWindow
                self.isDragActive = false

                let primer = DispatchWorkItem {
                    self.isDragActive = true
                    NotificationCenter.default.post(
                        name: .capsuleDragStarted,
                        object: nil
                    )
                }
                self.dragPrimer = primer
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: primer)
                return event

            case .leftMouseDragged:
                let current = event.locationInWindow
                if self.isDragActive, let prev = self.previousDragLocation {
                    let dx = current.x - prev.x
                    let dy = current.y - prev.y
                    var origin = self.window?.frame.origin ?? .zero
                    origin.x += dx
                    origin.y += dy
                    self.window?.setFrameOrigin(origin)
                }
                self.previousDragLocation = current
                return self.isDragActive ? nil : event

            case .leftMouseUp:
                self.dragPrimer?.cancel()
                self.dragPrimer = nil
                self.isDragActive = false
                self.previousDragLocation = nil
                self.saveFrame()
                NotificationCenter.default.post(
                    name: .capsuleDragEnded,
                    object: nil
                )
                return event

            default:
                return event
            }
        }
    }

    private func observeExpandedState() {
        observers.append(
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

                // Update cornerRadius before animated resize so it animates with the frame
                let cornerRadius: CGFloat
                if isExpanded {
                    cornerRadius = 12
                } else {
                    cornerRadius = self.settingsStore.collapsedStyle == "dot" ? 6 : 18
                }
                window.contentView?.layer?.cornerRadius = cornerRadius

                let newFrame = NSRect(
                    x: currentFrame.midX - targetSize.width / 2,
                    y: currentFrame.maxY - targetSize.height,
                    width: targetSize.width,
                    height: targetSize.height
                )

                window.setFrame(newFrame, display: true, animate: true)
                self.isExpanded = isExpanded

                // When expanded, activate app and make key so TextField can receive input
                if isExpanded {
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKey()
                }
            }
        )

        // Listen for collapsed style changes via UserDefaults
        observers.append(
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self = self, let window = self.window, !self.isExpanded else { return }
                let style = UserDefaults.standard.string(forKey: SettingsKey.collapsedStyle.rawValue) ?? "capsule"
                let radius: CGFloat = style == "dot" ? 6 : 18
                window.contentView?.layer?.cornerRadius = radius
                let size = style == "dot" ? Self.dotCollapsedSize : Self.capsuleCollapsedSize
                if window.frame.size != size {
                    let newFrame = NSRect(
                        x: window.frame.midX - size.width / 2,
                        y: window.frame.maxY - size.height,
                        width: size.width,
                        height: size.height
                    )
                    window.setFrame(newFrame, display: true, animate: true)
                }
            }
        )

        // Listen for reset position request
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .resetCapsulePosition,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self = self,
                      let window = self.window,
                      let screen = NSScreen.main else { return }

                let size = self.settingsStore.collapsedStyle == "dot" ? Self.dotCollapsedSize : Self.capsuleCollapsedSize
                let screenWidth = screen.visibleFrame.width
                let screenHeight = screen.visibleFrame.maxY

                let x = (screenWidth - size.width) / 2
                let y = screenHeight - size.height - 40
                let newFrame = NSRect(x: x, y: y, width: size.width, height: size.height)

                window.setFrame(newFrame, display: true, animate: true)
                UserDefaults.standard.removeObject(forKey: SettingsKey.capsuleWindowFrame.rawValue)
            }
        )

        // Listen for show floating panel toggle
        observers.append(
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
        )
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
        UserDefaults.standard.set(frameDict, forKey: SettingsKey.capsuleWindowFrame.rawValue)
    }

    private static func loadFrame(style: String) -> NSRect {
        let size = style == "dot" ? dotCollapsedSize : capsuleCollapsedSize

        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: size.width, height: size.height)
        }
        let screenWidth = screen.visibleFrame.width
        let screenHeight = screen.visibleFrame.maxY

        var x = (screenWidth - size.width) / 2
        var y = screenHeight - size.height - 40

        // Restore saved position, clamping to visible screen bounds
        if let dict = UserDefaults.standard.dictionary(forKey: SettingsKey.capsuleWindowFrame.rawValue) as? [String: CGFloat],
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
