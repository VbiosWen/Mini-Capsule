// Mini Capsule/UI/PopoverEditorView.swift
import SwiftUI

struct PopoverEditorView: View {
    let item: ClipItem
    let onSave: (String) -> Void

    @State private var editedText: String
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(item: ClipItem, onSave: @escaping (String) -> Void) {
        self.item = item
        self.onSave = onSave
        _editedText = State(initialValue: item.textContent ?? "")
    }

    var body: some View {
        VStack(spacing: 12) {
            TextEditor(text: $editedText)
                .font(.system(size: 12, design: .monospaced))
                .frame(minWidth: 250, minHeight: 120)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(8)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 12) {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))

                Spacer()

                Button("保存") {
                    onSave(editedText)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .font(.system(size: 12))
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }
}
