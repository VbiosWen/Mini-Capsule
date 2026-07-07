// Mini Capsule/UI/CapsuleViewModel.swift
import SwiftUI
import Foundation

@MainActor
@Observable
final class CapsuleViewModel {
    // MARK: - Published State

    var isExpanded = false
    var isExpandingReady = false
    var isCapturing = false
    var isDragging = false

    // MARK: - Dependencies

    let settings: SettingsStore

    // MARK: - Internal

    private var hoverTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?

    // MARK: - Computed

    var windowOpacity: Double {
        if isExpanded { return 1.0 }
        let unfocused = settings.panelOpacityUnfocused
        return unfocused > 0 ? unfocused : 0.6
    }

    var expandDelay: Double {
        settings.hoverExpandDelay > 0 ? settings.hoverExpandDelay : 0.3
    }

    var collapseDelay: Double {
        settings.hoverCollapseDelay > 0 ? settings.hoverCollapseDelay : 1.0
    }

    // MARK: - Init

    init(settings: SettingsStore) {
        self.settings = settings
    }

    // MARK: - Hover State Machine

    func onHoverEnter() {
        hoverTask?.cancel()
        guard !isDragging else { return }
        isExpandingReady = false
        hoverTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.expandDelay))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                self.isExpanded = true
            }
            self.postExpandedNotification()
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self.isExpandingReady = true
        }
    }

    func onHoverExit() {
        hoverTask?.cancel()
        isExpandingReady = false
        guard !isDragging else { return }
        hoverTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.collapseDelay))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                self.isExpanded = false
            }
            self.postExpandedNotification()
        }
    }

    func collapse() {
        hoverTask?.cancel()
        guard isExpanded else { return }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
            isExpanded = false
        }
        postExpandedNotification()
    }

    // MARK: - Drag State

    func onDragStart() {
        isDragging = true
        if isExpanded {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isExpanded = false
            }
            postExpandedNotification()
        }
    }

    func onDragEnd() {
        isDragging = false
    }

    // MARK: - Capture Animation

    func onNewItemCaptured() {
        isCapturing = true
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.isCapturing = false
        }
    }

    // MARK: - Private

    private func postExpandedNotification() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(
                name: .capsuleDidChangeExpanded,
                object: nil,
                userInfo: ["isExpanded": self.isExpanded]
            )
        }
    }
}
