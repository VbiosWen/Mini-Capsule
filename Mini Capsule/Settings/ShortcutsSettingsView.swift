// Mini Capsule/Settings/ShortcutsSettingsView.swift
import SwiftUI
import AppKit
import Combine

// MARK: - Capture Manager

@MainActor
final class ShortcutCaptureManager: ObservableObject {
    @Published var isRecording = false
    @Published var capturedShortcut: String?
    private var monitor: Any?

    func startCapture() {
        isRecording = true
        capturedShortcut = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleEvent(event)
            return nil
        }
        // Timeout after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, self.isRecording else { return }
            self.stopCapture()
        }
    }

    func stopCapture() {
        if let mon = monitor {
            NSEvent.removeMonitor(mon)
        }
        monitor = nil
        isRecording = false
    }

    private func handleEvent(_ event: NSEvent) {
        var parts: [String] = []
        if event.modifierFlags.contains(.command) { parts.append("cmd") }
        if event.modifierFlags.contains(.shift) { parts.append("shift") }
        if event.modifierFlags.contains(.option) { parts.append("option") }
        if event.modifierFlags.contains(.control) { parts.append("control") }
        guard let key = event.charactersIgnoringModifiers?.lowercased(),
              !key.isEmpty else { return }
        let modifierKeys: Set<String> = ["", "\u{7F}"]
        guard !modifierKeys.contains(key) else { return }
        parts.append(key)
        capturedShortcut = parts.joined(separator: "+")
        stopCapture()
    }
}

// MARK: - Settings View

struct ShortcutsSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @StateObject private var captureManager = ShortcutCaptureManager()

    var body: some View {
        Form {
            Section {
                ShortcutRowView(
                    label: "显示/隐藏胶囊",
                    shortcut: $settings.showHideShortcut,
                    allLabels: allLabels
                )
                ShortcutRowView(
                    label: "快速粘贴上一条",
                    shortcut: $settings.quickPasteShortcut,
                    allLabels: allLabels
                )
                ShortcutRowView(
                    label: "切换置顶",
                    shortcut: $settings.togglePinShortcut,
                    allLabels: allLabels
                )
            } header: {
                Text("快捷键")
            } footer: {
                Text("点击\u{201C}录制\u{201D}后按下键盘组合键。留空表示不设置快捷键。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 250)
    }

    private var allLabels: [String] {
        ["显示/隐藏胶囊", "快速粘贴上一条", "切换置顶"]
    }
}

// MARK: - Row View

private struct ShortcutRowView: View {
    let label: String
    @Binding var shortcut: String
    let allLabels: [String]

    @StateObject private var captureManager = ShortcutCaptureManager()

    @State private var conflictMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .frame(width: 130, alignment: .leading)

                Text(displayString)
                    .foregroundColor(captureManager.isRecording ? .red : .secondary)
                    .frame(minWidth: 80, alignment: .leading)

                Button(captureManager.isRecording ? "按下快捷键..." : "录制") {
                    if captureManager.isRecording {
                        captureManager.stopCapture()
                    } else {
                        captureManager.startCapture()
                    }
                }
                .buttonStyle(.bordered)
                .tint(captureManager.isRecording ? .red : nil)

                if !shortcut.isEmpty && !captureManager.isRecording {
                    Button(action: {
                        shortcut = ""
                        conflictMessage = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }

            if let conflict = conflictMessage, !shortcut.isEmpty {
                Text("⚠️ \(conflict)")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .padding(.leading, 130)
            }
        }
        .onChange(of: captureManager.capturedShortcut) { _, newValue in
            if let new = newValue {
                shortcut = new
                checkConflicts(new)
            }
        }
    }

    private var displayString: String {
        if captureManager.isRecording {
            return "按下快捷键..."
        }
        if shortcut.isEmpty {
            return "未设置"
        }
        return shortcut
            .replacingOccurrences(of: "cmd", with: "⌘")
            .replacingOccurrences(of: "shift", with: "⇧")
            .replacingOccurrences(of: "option", with: "⌥")
            .replacingOccurrences(of: "control", with: "⌃")
            .replacingOccurrences(of: "+", with: "")
            .uppercased()
    }

    private func checkConflicts(_ newShortcut: String) {
        // Check other Mini Capsule shortcuts
        let allBindings: [String: String] = [
            "显示/隐藏胶囊": UserDefaults.standard.string(forKey: "showHideShortcut") ?? "cmd+shift+V",
            "快速粘贴上一条": UserDefaults.standard.string(forKey: "quickPasteShortcut") ?? "cmd+shift+C",
            "切换置顶": UserDefaults.standard.string(forKey: "togglePinShortcut") ?? "",
        ]
        for (otherLabel, otherShortcut) in allBindings {
            if otherLabel != label && otherShortcut == newShortcut && !newShortcut.isEmpty {
                conflictMessage = "与「\(otherLabel)」冲突"
                return
            }
        }
        let systemConflicts: [String: String] = [
            "cmd+space": "Spotlight",
            "cmd+shift+3": "截屏",
            "cmd+shift+4": "截屏选区",
            "cmd+shift+5": "截屏录制",
            "cmd+tab": "应用切换器",
        ]
        if let name = systemConflicts[newShortcut] {
            conflictMessage = "与系统快捷键（\(name)）冲突"
            return
        }
        conflictMessage = nil
    }
}
