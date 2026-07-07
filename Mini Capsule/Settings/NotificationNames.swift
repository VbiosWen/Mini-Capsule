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

    /// Posted when Escape key is pressed in the expanded capsule.
    static let capsuleEscapePressed = Notification.Name("capsuleEscapePressed")

    /// Posted to edit a clip item's text content.
    /// UserInfo contains `["item": ClipItem, "content": String]`.
    static let capsuleEditTextItem = Notification.Name("capsuleEditTextItem")

    /// Posted to paste a clip item to the front application.
    /// UserInfo contains `["item": ClipItem]`.
    static let capsulePasteItemToFront = Notification.Name("capsulePasteItemToFront")

    /// Posted to toggle the pin state of a clip item.
    /// UserInfo contains `["item": ClipItem]`.
    static let capsuleTogglePinItem = Notification.Name("capsuleTogglePinItem")

    /// Posted to request editing a text item. UserInfo: ["itemID": UUID, "content": String]
    static let editTextItem = Notification.Name("editTextItem")

    /// Posted to request pasting an item to frontmost app. UserInfo: ["itemID": UUID]
    static let pasteItemToFront = Notification.Name("pasteItemToFront")

    /// Posted to toggle pin status of an item. UserInfo: ["itemID": UUID]
    static let togglePinItem = Notification.Name("togglePinItem")
}
