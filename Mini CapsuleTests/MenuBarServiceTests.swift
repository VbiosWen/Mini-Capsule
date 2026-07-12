import Testing
import AppKit
@testable import Mini_Capsule

@MainActor
struct MenuBarServiceTests {
    @Test func menuBarIconIsAppIconSizedForStatusBar() {
        let icon = MenuBarService.menuBarIcon()
        #expect(icon != nil, "app icon should resolve from the asset catalog")
        #expect(icon?.size == NSSize(width: 18, height: 18))
    }

    @Test func menuBarIconDoesNotMutateSharedNamedImage() {
        _ = MenuBarService.menuBarIcon()
        // The cached named image must keep its original size after we derive the small copy.
        if let shared = NSImage(named: "AppIcon") {
            #expect(max(shared.size.width, shared.size.height) > 18)
        }
    }
}
