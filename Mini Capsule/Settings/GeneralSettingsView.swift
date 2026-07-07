// Mini Capsule/Settings/GeneralSettingsView.swift
import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @Environment(SettingsStore.self) var settings

    var body: some View {
        Form {
            Section {
                Toggle("开机启动", isOn: Bindable(settings).launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            settings.launchAtLogin = !newValue
                        }
                    }

                Toggle("菜单栏显示", isOn: Bindable(settings).showInMenuBar)
                    .onChange(of: settings.showInMenuBar) { _, _ in
                        ensureOneModeEnabled()
                    }

                Toggle("屏幕悬浮窗", isOn: Bindable(settings).showFloatingPanel)
                    .onChange(of: settings.showFloatingPanel) { _, newValue in
                        ensureOneModeEnabled()
                        if newValue {
                            NotificationCenter.default.post(
                                name: .showFloatingPanelChanged,
                                object: nil,
                                userInfo: ["show": true]
                            )
                        } else {
                            NotificationCenter.default.post(
                                name: .showFloatingPanelChanged,
                                object: nil,
                                userInfo: ["show": false]
                            )
                        }
                    }
            } header: {
                Text("展示")
            }

            Section {
                LabeledContent("折叠形态") {
                    Picker("", selection: Bindable(settings).collapsedStyle) {
                        Text("胶囊").tag("capsule")
                        Text("圆点").tag("dot")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                .disabled(!settings.showFloatingPanel)

                LabeledContent("悬停展开延迟") {
                    Picker("", selection: Bindable(settings).hoverExpandDelay) {
                        Text("0.1 秒").tag(0.1)
                        Text("0.3 秒").tag(0.3)
                        Text("0.5 秒").tag(0.5)
                        Text("1.0 秒").tag(1.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                .disabled(!settings.showFloatingPanel)

                LabeledContent("离开折叠延迟") {
                    Picker("", selection: Bindable(settings).hoverCollapseDelay) {
                        Text("0.5 秒").tag(0.5)
                        Text("1.0 秒").tag(1.0)
                        Text("2.0 秒").tag(2.0)
                        Text("3.0 秒").tag(3.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                .disabled(!settings.showFloatingPanel)
            } header: {
                Text("悬浮窗行为")
            }

            if !settings.showInMenuBar && !settings.showFloatingPanel {
                Text("⚠️ 至少需要开启一种展示方式")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }

            Section {
                Button(action: {
                    Self.resetCapsulePosition()
                }) {
                    Label("重置浮动窗位置", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("高级")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 370)
    }

    static func resetCapsulePosition() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.capsuleWindowFrame.rawValue)
        NotificationCenter.default.post(name: .resetCapsulePosition, object: nil)
    }

    private func ensureOneModeEnabled() {
        if !settings.showInMenuBar && !settings.showFloatingPanel {
            settings.showInMenuBar = true
        }
    }
}
