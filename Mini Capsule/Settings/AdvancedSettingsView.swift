// Mini Capsule/Settings/AdvancedSettingsView.swift
import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct AdvancedSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.modelContext) private var modelContext

    @State private var isOperating = false
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var alertTitle = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("iCloud 同步")
                        Text("即将推出")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: .constant(false))
                        .disabled(true)
                }
            } header: {
                Text("同步")
            }

            Section {
                Button("导出数据...") {
                    exportData()
                }
                .disabled(isOperating)

                Button("导入数据...") {
                    importData()
                }
                .disabled(isOperating)
            } header: {
                Text("数据管理")
            }

            Section {
                Button("清空所有历史") {
                    alertTitle = "清空所有历史"
                    alertMessage = "此操作将删除所有剪贴板历史记录，且不可撤销。确定要继续吗？"
                    showAlert = true
                }
                .foregroundColor(.red)

                Button("重置所有设置") {
                    alertTitle = "重置所有设置"
                    alertMessage = "所有设置将恢复为默认值。确定要继续吗？"
                    showAlert = true
                }
            } header: {
                Text("危险操作")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 300)
        .alert(alertTitle, isPresented: $showAlert) {
            Button("取消", role: .cancel) {}
            Button("确定", role: .destructive) {
                if alertTitle == "清空所有历史" {
                    settings.clearAllHistory(context: modelContext)
                } else if alertTitle == "重置所有设置" {
                    settings.resetAll()
                }
            }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func exportData() {
        isOperating = true
        defer { isOperating = false }

        guard let data = settings.exportData(context: modelContext) else {
            alertTitle = "导出失败"
            alertMessage = "无法读取剪贴板数据。"
            showAlert = true
            return
        }

        let panel = NSSavePanel()
        panel.title = "导出剪贴板数据"
        panel.nameFieldStringValue = "mini-capsule-export.json"
        panel.allowedContentTypes = [UTType.json]

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try data.write(to: url)
                } catch {
                    alertTitle = "导出失败"
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }

    private func importData() {
        isOperating = true
        defer { isOperating = false }

        let panel = NSOpenPanel()
        panel.title = "导入剪贴板数据"
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false

        panel.begin { response in
            if response == .OK, let url = panel.urls.first {
                do {
                    let data = try Data(contentsOf: url)
                    guard !data.isEmpty else {
                        alertTitle = "导入失败"
                        alertMessage = "文件为空或格式不正确。"
                        showAlert = true
                        return
                    }
                    try settings.importData(data, context: modelContext)
                } catch let error as DecodingError {
                    alertTitle = "导入失败"
                    alertMessage = "JSON 格式不正确：\(error.localizedDescription)"
                    showAlert = true
                } catch {
                    alertTitle = "导入失败"
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }
}
