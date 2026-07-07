import Testing
import Foundation
@testable import Mini_Capsule

struct NotificationNamesTests {
    @Test func settingsNotificationsHaveCorrectRawValues() async throws {
        #expect(Notification.Name.pollingIntervalDidChange == Notification.Name("SettingsPollingIntervalDidChange"))
        #expect(Notification.Name.showFloatingPanelChanged == Notification.Name("ShowFloatingPanelChanged"))
    }

    @Test func capsuleNotificationsHaveCorrectRawValues() async throws {
        #expect(Notification.Name.capsuleDidChangeExpanded == Notification.Name("capsuleDidChangeExpanded"))
        #expect(Notification.Name.capsuleDragStarted == Notification.Name("capsuleDragStarted"))
        #expect(Notification.Name.capsuleDragEnded == Notification.Name("capsuleDragEnded"))
        #expect(Notification.Name.resetCapsulePosition == Notification.Name("resetCapsulePosition"))
    }

    @Test func allNotificationValuesAreUnique() async throws {
        let values: Set<String> = [
            "SettingsPollingIntervalDidChange", "ShowFloatingPanelChanged",
            "capsuleDidChangeExpanded", "capsuleDragStarted",
            "capsuleDragEnded", "resetCapsulePosition"
        ]
        #expect(values.count == 6)
    }
}
