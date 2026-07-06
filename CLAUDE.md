# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Build the project
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' build

# Run unit tests (Swift Testing framework)
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' test

# Run a single unit test (Swift Testing — filter by test name)
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleTests/Mini_CapsuleTests/testExample test

# Run UI tests (XCTest)
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Mini_CapsuleUITests test

# Run on macOS
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build
```

To open in Xcode: `open "Mini Capsule.xcodeproj"`

## Architecture

This is a **multi-platform SwiftUI app** using **SwiftData** for persistence. It targets iOS, macOS, and visionOS from a single codebase.

### Data Layer
- **SwiftData** with a `ModelContainer` defined in `Mini_CapsuleApp.swift`. The schema currently contains a single entity: `Item`.
- `@Model final class Item` with one property, `timestamp: Date`. Add new `@Model` classes alongside `Item.swift` and register them in the `Schema` array in `Mini_CapsuleApp.swift`.

### View Layer
- **`ContentView`** is the root view. It uses `@Query` to fetch items from SwiftData and `@Environment(\.modelContext)` for mutations.
- **`NavigationViewWrapper`** (fileprivate in `ContentView.swift`) abstracts platform differences: uses `NavigationSplitView` on macOS and a plain `NavigationStack`-compatible container on iOS/visionOS.
- Conditional compilation (`#if os(macOS)`, `#if os(iOS)`) handles platform-specific UI like the `EditButton` placement and split view styling.

### App Capabilities
- **CloudKit** is enabled (see entitlements) for potential iCloud sync, but no CloudKit containers are configured yet.
- **Remote notifications** (background mode) support is declared in `Info.plist`.
- The entitlements use `aps-environment: development` — release builds should switch this to `production`.

### Testing Strategy
- **Unit tests** use the modern **Swift Testing** framework (`import Testing`, `@Test`, `#expect`), not XCTest.
- **UI tests** use **XCTest** (`XCUIApplication`, `XCTAssert`).
- SwiftData previews and tests use `inMemory: true` to avoid persisting test data.

### Cross-Platform Notes
- Deployment target is **26.5** across all platforms (iOS, macOS, visionOS).
- Swift 5.0.
- The `TARGETED_DEVICE_FAMILY` is `1,2,7` (iOS, macOS, visionOS).
- Platform-conditional code uses `#if os(macOS)` / `#if os(iOS)` — add `#if os(xrOS)` for visionOS-specific code.
