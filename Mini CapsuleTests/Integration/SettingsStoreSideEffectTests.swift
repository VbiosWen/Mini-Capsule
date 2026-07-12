import Testing
import Foundation
@testable import Mini_Capsule

@MainActor
@Suite(.tags(.integration), .serialized)
struct SettingsStoreSideEffectTests {
    /// Count posts of `name` while running `body`, then clean up.
    private func countPosts(of name: Notification.Name, _ body: () -> Void) -> Int {
        var count = 0
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        body()
        return count
    }

    @Test func showHideShortcutPostsShortcutsDidChange() {
        #expect(countPosts(of: .shortcutsDidChange) { SettingsStore().showHideShortcut = "cmd+shift+x" } == 1)
    }

    @Test func quickPasteShortcutPostsShortcutsDidChange() {
        #expect(countPosts(of: .shortcutsDidChange) { SettingsStore().quickPasteShortcut = "cmd+shift+y" } == 1)
    }

    @Test func togglePinShortcutPostsShortcutsDidChange() {
        #expect(countPosts(of: .shortcutsDidChange) { SettingsStore().togglePinShortcut = "cmd+shift+p" } == 1)
    }

    @Test func collapsedStylePostsCapsuleStyleDidChange() {
        #expect(countPosts(of: .capsuleStyleDidChange) { SettingsStore().collapsedStyle = "dot" } == 1)
    }

    @Test func ringDiameterPostsCapsuleStyleDidChange() {
        #expect(countPosts(of: .capsuleStyleDidChange) { SettingsStore().ringDiameter = 42 } == 1)
    }

    @Test func nonSideEffectSetterPostsNothing() {
        let shortcuts = countPosts(of: .shortcutsDidChange) { SettingsStore().historyMaxCount = 999 }
        let style = countPosts(of: .capsuleStyleDidChange) { SettingsStore().dedupEnabled = false }
        #expect(shortcuts == 0)
        #expect(style == 0)
    }
}
