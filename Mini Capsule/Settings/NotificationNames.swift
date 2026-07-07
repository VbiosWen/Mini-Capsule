// Mini Capsule/Settings/NotificationNames.swift
import Foundation

// MARK: - Settings Notifications

extension Notification.Name {
    /// Posted when the polling interval setting changes.
    static let pollingIntervalDidChange = Notification.Name("SettingsPollingIntervalDidChange")

    /// Posted when the floating panel visibility toggle changes.
    /// UserInfo contains `["show": Bool]`.
    static let showFloatingPanelChanged = Notification.Name("ShowFloatingPanelChanged")
}

// MARK: - Capsule Notifications

extension Notification.Name {
    /// Posted when the capsule expanded/collapsed state changes.
    /// UserInfo contains `["isExpanded": Bool]`.
    static let capsuleDidChangeExpanded = Notification.Name("capsuleDidChangeExpanded")

    /// Posted when a drag operation starts on the capsule window.
    static let capsuleDragStarted = Notification.Name("capsuleDragStarted")

    /// Posted when a drag operation ends on the capsule window.
    static let capsuleDragEnded = Notification.Name("capsuleDragEnded")

    /// Posted to request resetting the capsule window position to default.
    static let resetCapsulePosition = Notification.Name("resetCapsulePosition")
}
