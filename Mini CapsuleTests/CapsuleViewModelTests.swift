// Mini CapsuleTests/CapsuleViewModelTests.swift
import Testing
import Foundation
@testable import Mini_Capsule

@MainActor
struct CapsuleViewModelTests {

    @Test func initialStateAllDefaults() async throws {
        let settings = SettingsStore()
        let vm = CapsuleViewModel(settings: settings)

        #expect(vm.isExpanded == false)
        #expect(vm.isExpandingReady == false)
        #expect(vm.isCapturing == false)
        #expect(vm.isDragging == false)
        #expect(vm.windowOpacity == settings.panelOpacityUnfocused)

        settings.resetAll()
    }

    @Test func onHoverEnterSetsExpandedAfterDelay() async throws {
        let settings = SettingsStore()
        settings.hoverExpandDelay = 0.1
        let vm = CapsuleViewModel(settings: settings)

        vm.onHoverEnter()
        #expect(vm.isExpanded == false) // not yet

        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.isExpanded == true)

        settings.resetAll()
    }

    @Test func onHoverEnterThenQuickExitDoesNotExpand() async throws {
        let settings = SettingsStore()
        settings.hoverExpandDelay = 0.5
        let vm = CapsuleViewModel(settings: settings)

        vm.onHoverEnter()
        try await Task.sleep(for: .milliseconds(50))
        vm.onHoverExit()

        try await Task.sleep(for: .milliseconds(600))
        #expect(vm.isExpanded == false)

        settings.resetAll()
    }

    @Test func onHoverExitCollapsesAfterDelay() async throws {
        let settings = SettingsStore()
        settings.hoverExpandDelay = 0.05
        settings.hoverCollapseDelay = 0.1
        let vm = CapsuleViewModel(settings: settings)

        vm.onHoverEnter()
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.isExpanded == true)

        vm.onHoverExit()
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.isExpanded == false)

        settings.resetAll()
    }

    @Test func collapseImmediatelyCollapses() async throws {
        let settings = SettingsStore()
        settings.hoverExpandDelay = 0.05
        let vm = CapsuleViewModel(settings: settings)

        vm.onHoverEnter()
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.isExpanded == true)

        vm.collapse()
        #expect(vm.isExpanded == false)

        settings.resetAll()
    }

    @Test func onDragStartDisablesHover() async throws {
        let settings = SettingsStore()
        settings.hoverExpandDelay = 0.1
        let vm = CapsuleViewModel(settings: settings)

        vm.onDragStart()
        #expect(vm.isDragging == true)

        vm.onHoverEnter()
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.isExpanded == false) // hover blocked by drag

        settings.resetAll()
    }

    @Test func onDragEndReenablesHover() async throws {
        let settings = SettingsStore()
        settings.hoverExpandDelay = 0.1
        let vm = CapsuleViewModel(settings: settings)

        vm.onDragStart()
        vm.onDragEnd()
        #expect(vm.isDragging == false)

        vm.onHoverEnter()
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.isExpanded == true)

        settings.resetAll()
    }

    @Test func onNewItemCapturedTriggersAnimation() async throws {
        let settings = SettingsStore()
        let vm = CapsuleViewModel(settings: settings)

        vm.onNewItemCaptured()
        #expect(vm.isCapturing == true)

        try await Task.sleep(for: .seconds(2.1))
        #expect(vm.isCapturing == false)

        settings.resetAll()
    }

    @Test func windowOpacityExpandedIsOne() async throws {
        let settings = SettingsStore()
        settings.panelOpacityUnfocused = 0.5
        let vm = CapsuleViewModel(settings: settings)

        #expect(vm.windowOpacity == 0.5)

        vm.onHoverEnter()
        settings.hoverExpandDelay = 0.05
        vm.onHoverEnter()
        try await Task.sleep(for: .milliseconds(150))

        #expect(vm.windowOpacity == 1.0)

        settings.resetAll()
    }

    @Test func rapidHoverInOutInResolvesCorrectly() async throws {  // B5 fix verification
        let settings = SettingsStore()
        settings.hoverExpandDelay = 0.2
        settings.hoverCollapseDelay = 0.3
        let vm = CapsuleViewModel(settings: settings)

        vm.onHoverEnter()
        try await Task.sleep(for: .milliseconds(50))
        vm.onHoverExit()
        try await Task.sleep(for: .milliseconds(50))
        vm.onHoverEnter() // re-enter before collapse fires

        try await Task.sleep(for: .milliseconds(300))
        // Should be expanded (not collapsed, not race-conditioned)
        #expect(vm.isExpanded == true)

        settings.resetAll()
    }
}
