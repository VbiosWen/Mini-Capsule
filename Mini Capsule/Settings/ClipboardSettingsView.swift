// Mini Capsule/Settings/ClipboardSettingsView.swift
import SwiftUI

struct ClipboardSettingsView: View {
    @Environment(SettingsStore.self) var settings

    var body: some View {
        Form {
            Section {
                LabeledContent("历史记录上限") {
                    HStack(spacing: 8) {
                        Text("\(settings.historyMaxCount) 条")
                            .frame(minWidth: 50, alignment: .trailing)
                            .foregroundColor(.secondary)
                        Stepper("", value: Bindable(settings).historyMaxCount, in: 50...1000, step: 50)
                            .labelsHidden()
                    }
                }

                LabeledContent("图像大小限制") {
                    Picker("", selection: Bindable(settings).imageMaxSizeMB) {
                        Text("1 MB").tag(1)
                        Text("2 MB").tag(2)
                        Text("5 MB").tag(5)
                        Text("无限制").tag(0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }

                LabeledContent("轮询间隔") {
                    Picker("", selection: Bindable(settings).pollingInterval) {
                        Text("0.5 秒").tag(0.5)
                        Text("1 秒").tag(1.0)
                        Text("2 秒").tag(2.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                .onChange(of: settings.pollingInterval) { _, _ in
                    NotificationCenter.default.post(
                        name: .pollingIntervalDidChange,
                        object: nil
                    )
                }
            } header: {
                Text("存储")
            }

            Section {
                Toggle("启动时清理历史", isOn: Bindable(settings).cleanupOnStartup)
                Toggle("内容去重", isOn: Bindable(settings).dedupEnabled)
            } header: {
                Text("行为")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 300)
    }
}
