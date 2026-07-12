//
//  CapsuleSmokeUITests.swift
//  Mini CapsuleUITests
//
//  Created by vbiso on 2026/7/12.
//

import XCTest

final class CapsuleSmokeUITests: XCTestCase {
    func testAppLaunchesAndTerminatesCleanly() {
        let app = XCUIApplication()
        app.launch()
        // Mini Capsule is a menu-bar / floating-panel app (LSUIElement),
        // so it runs in the background rather than as a foreground window.
        let isRunning = app.state == .runningForeground || app.state == .runningBackground
        XCTAssertTrue(isRunning, "app should be running after launch (state: \(app.state.rawValue))")
        app.terminate()
        XCTAssertEqual(app.state, .notRunning, "app should terminate cleanly")
    }
}
