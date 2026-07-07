// Mini Capsule/Settings/AppearanceSettingsView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AppearanceSettingsView: View {
    @Environment(SettingsStore.self) var settings

    @State private var thumbnailImage: NSImage?
    @State private var isChoosingImage = false

    var body: some View {
        Form {
            Section {
                LabeledContent("失焦不透明度") {
                    HStack(spacing: 8) {
                        Slider(value: Bindable(settings).panelOpacityUnfocused, in: 0.3...1.0, step: 0.05)
                            .frame(width: 150)
                        Text(String(format: "%.0f%%", settings.panelOpacityUnfocused * 100))
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                Text("透明度")
            } footer: {
                Text("悬浮窗未聚焦或鼠标未悬停时的透明度。聚焦时始终不透明。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("展开面板背景图")
                        if let image = thumbnailImage {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            Text("未设置")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button("选择图片...") {
                        chooseImage()
                    }
                }

                if !settings.backgroundImageData.isEmpty {
                    Button("清除背景图") {
                        settings.backgroundImageData = Data()
                        thumbnailImage = nil
                    }
                    .foregroundColor(.red)
                }
            } header: {
                Text("背景")
            }

            Section {
                LabeledContent("圆环直径") {
                    HStack(spacing: 8) {
                        Slider(value: Bindable(settings).ringDiameter, in: 20...120, step: 2)
                            .frame(width: 150)
                        Text("\(Int(settings.ringDiameter)) px")
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                Text("圆环")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 320)
        .onAppear {
            if !settings.backgroundImageData.isEmpty {
                thumbnailImage = NSImage(data: settings.backgroundImageData)
            }
        }
        .onChange(of: settings.backgroundImageData) { _, newData in
            if !newData.isEmpty {
                thumbnailImage = NSImage(data: newData)
            } else {
                thumbnailImage = nil
            }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = "选择背景图片"
        panel.allowedContentTypes = [UTType.image]
        panel.allowsMultipleSelection = false

        panel.begin { response in
            if response == .OK, let url = panel.urls.first,
               let imageData = try? Data(contentsOf: url) {
                // Compress if over 2MB
                let compressed = capImageSize(imageData, maxBytes: 2_000_000)
                settings.backgroundImageData = compressed
            }
        }
    }

    private func capImageSize(_ data: Data, maxBytes: Int) -> Data {
        guard data.count > maxBytes,
              let image = NSImage(data: data) else { return data }
        let scale = sqrt(Double(maxBytes) / Double(data.count))
        let newSize = NSSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        else { return data }
        return jpeg
    }
}
