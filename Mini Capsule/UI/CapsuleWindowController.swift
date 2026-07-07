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
    private var dragInitialMouse: NSPoint?
    private var dragInitialOrigin: NSPoint?

    private static let capsuleCollapsedSize = NSSize(width: 200, height: 36)
    private var dotCollapsedSize: NSSize {
        let diameter = settingsStore.ringDiameter
        return NSSize(width: diameter, height: diameter)
    }
    private static let iconCollapsedSize = NSSize(width: 24, height: 24)
    private static let expandedSize = NSSize(width: 280, height: 360)

    private var currentCollapsedSize: NSSize {
        switch settingsStore.collapsedStyle {
        case "dot": return dotCollapsedSize
        case "icon": return Self.iconCollapsedSize
        default: return Self.capsuleCollapsedSize
        }
    }

    init(modelContainer: ModelContainer, settingsStore: SettingsStore) {
        self.modelContainer = modelContainer
        self.settingsStore = settingsStore

        let savedFrame = Self.loadFrame(style: settingsStore.collapsedStyle, frameData: settingsStore.capsuleWindowFrame)

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

        let capsuleView = CapsuleView(
            modelContext: modelContainer.mainContext,
            settings: settingsStore
        )
        .modelContainer(modelContainer)
        .environment(settingsStore)

        // Wrap the hosting view in a plain NSView so that the window's contentView
        // is NOT an NSHostingView. This prevents SwiftUI's updateAnimatedWindowSize
        // from trying to auto-resize the window during layout, which causes a
        // constraint-layout infinite loop when SwiftUI animations are running.
        let hostingView = NSHostingView(rootView: capsuleView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let clipView = NSView()
        clipView.wantsLayer = true
        clipView.layer?.masksToBounds = true
        let initCornerRadius: CGFloat
        switch settingsStore.collapsedStyle {
        case "dot": initCornerRadius = settingsStore.ringDiameter / 2
        case "icon": initCornerRadius = 6
        default: initCornerRadius = 18
        }
        clipView.layer?.cornerRadius = initCornerRadius

        clipView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: clipView.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: clipView.bottomAnchor)
        ])

        panel.contentView = clipView

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
                self.dragInitialMouse = NSEvent.mouseLocation
                self.dragInitialOrigin = self.window?.frame.origin
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
                if self.isDragActive,
                   let initMouse = self.dragInitialMouse,
                   let initOrigin = self.dragInitialOrigin {
                    let current = NSEvent.mouseLocation
                    let dx = current.x - initMouse.x
                    let dy = current.y - initMouse.y
                    self.window?.setFrameOrigin(
                        NSPoint(x: initOrigin.x + dx, y: initOrigin.y + dy)
                    )
                }
                return self.isDragActive ? nil : event

            case .leftMouseUp:
                self.dragPrimer?.cancel()
                self.dragPrimer = nil
                self.isDragActive = false
                self.dragInitialMouse = nil
                self.dragInitialOrigin = nil
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
                    switch self.settingsStore.collapsedStyle {
                    case "dot": cornerRadius = self.settingsStore.ringDiameter / 2
                    case "icon": cornerRadius = 6
                    default: cornerRadius = 18
                    }
                }
                let newFrame = NSRect(
                    x: currentFrame.midX - targetSize.width / 2,
                    y: currentFrame.maxY - targetSize.height,
                    width: targetSize.width,
                    height: targetSize.height
                )

                if isExpanded {
                    // Expand: resize window immediately so content has room to animate in.
                    window.contentView?.layer?.cornerRadius = cornerRadius
                    window.setFrame(newFrame, display: true, animate: false)
                    self.isExpanded = isExpanded
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKey()
                } else {
                    // Collapse: delay the window shrink until the SwiftUI spring
                    // animation completes. During the transition, both expanded and
                    // collapsed views are in the hierarchy, so the hosting view
                    // reports the expanded intrinsic size. Shrinking too early causes
                    // NSHostingView.updateAnimatedWindowSize to fight our frame change,
                    // triggering a constraint-layout infinite loop (NSGenericException).
                    self.isExpanded = isExpanded
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                        guard let self = self, let window = self.window, !self.isExpanded else { return }
                        window.contentView?.layer?.cornerRadius = cornerRadius
                        window.setFrame(newFrame, display: true, animate: false)
                    }
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
                let radius: CGFloat
                switch style {
                case "dot": radius = self.settingsStore.ringDiameter / 2
                case "icon": radius = 6
                default: radius = 18
                }
                window.contentView?.layer?.cornerRadius = radius
                let size: NSSize
                switch style {
                case "dot": size = self.dotCollapsedSize
                case "icon": size = Self.iconCollapsedSize
                default: size = Self.capsuleCollapsedSize
                }
                if window.frame.size != size {
                    let newFrame = NSRect(
                        x: window.frame.midX - size.width / 2,
                        y: window.frame.maxY - size.height,
                        width: size.width,
                        height: size.height
                    )
                    window.setFrame(newFrame, display: true, animate: false)
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

                let size: NSSize
                switch self.settingsStore.collapsedStyle {
                case "dot": size = self.dotCollapsedSize
                case "icon": size = Self.iconCollapsedSize
                default: size = Self.capsuleCollapsedSize
                }
                let screenWidth = screen.visibleFrame.width
                let screenHeight = screen.visibleFrame.maxY

                let x = (screenWidth - size.width) / 2
                let y = screenHeight - size.height - 40
                let newFrame = NSRect(x: x, y: y, width: size.width, height: size.height)

                window.setFrame(newFrame, display: true, animate: false)
                self.settingsStore.capsuleWindowFrame = Data()
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
        if let data = try? JSONEncoder().encode(frameDict) {
            settingsStore.capsuleWindowFrame = data
        }
    }

    private static func loadFrame(style: String, frameData: Data) -> NSRect {
        let size: NSSize
        switch style {
        case "dot":
            let diameter = UserDefaults.standard.object(forKey: SettingsKey.ringDiameter.rawValue) as? Double ?? 60
            size = NSSize(width: diameter, height: diameter)
        case "icon": size = Self.iconCollapsedSize
        default: size = Self.capsuleCollapsedSize
        }

        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: size.width, height: size.height)
        }
        let screenWidth = screen.visibleFrame.width
        let screenHeight = screen.visibleFrame.maxY

        var x = (screenWidth - size.width) / 2
        var y = screenHeight - size.height - 40

        // Restore saved position from SettingsStore, clamping to visible screen bounds
        if frameData.count > 0,
           let dict = try? JSONDecoder().decode([String: CGFloat].self, from: frameData),
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
