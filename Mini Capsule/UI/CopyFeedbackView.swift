// Mini Capsule/UI/CopyFeedbackView.swift
import SwiftUI

struct CopyFeedbackView: View {
    let viewModel: ClipboardListViewModel
    @State private var isVisible = false
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
            Text("已复制")
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        .offset(y: isVisible ? 0 : 20)
        .opacity(isVisible ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isVisible)
        .onChange(of: viewModel.lastCopiedItemID) { _, newValue in
            guard newValue != nil else { return }
            show()
        }
    }

    private func show() {
        feedbackTask?.cancel()
        isVisible = true
        feedbackTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            isVisible = false
        }
    }
}
