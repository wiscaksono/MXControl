@testable import AppCore
import Foundation
import Testing

struct AppStateTests {
    private func control(_ state: AppState, _ itemID: String) -> SettingControl? {
        state.sections.flatMap(\.items).first { $0.id == itemID }?.control
    }

    @Test func dummyStateHasExpectedDevices() {
        let state = DummyData.initialState()
        #expect(state.devices.map(\.name) == ["MX Master 3S", "MX Keys Mini", "Logitech Device"])
        #expect(state.details.count == 2)
        #expect(state.devices.last?.isConnected == false)
        #expect(state.warning == nil)
        #expect(state.route == .root)
    }

    @Test func dummyDataIsSelfConsistent() {
        let state = DummyData.initialState()
        #expect(Set(state.devices.map(\.id)).count == state.devices.count)

        for device in state.devices {
            #expect((0 ... 100).contains(device.battery.level))
            guard device.isConnected else { continue }
            let detail = state.details[device.id]
            #expect(detail?.device.id == device.id)
            #expect(detail?.sections.isEmpty == false)
        }

        for section in state.general {
            #expect(!section.items.isEmpty)
        }
    }

    @Test func settingValueMapsControls() {
        var mouse = DummyData.initialState(route: .device(DummyData.mouseID))
        #expect(mouse.settingValue("smartshift.active") == .bool(true))
        #expect(mouse.settingValue("dpi") == .int(1000))
        #expect(mouse.settingValue("smartshift.wheel_mode") == .picker(index: 0))
        #expect(mouse.settingValue("pointer.rate") == nil)

        mouse.setSlider("dpi", to: 1200)
        #expect(mouse.settingValue("dpi") == .int(1200))
    }

    @Test func scanCycleReplacesDevices() {
        var state = DummyData.warningState()
        state.devices = []
        state.details = [:]

        state.beginScan()
        #expect(state.isScanning)
        #expect(state.warning == nil)

        state.finishScan(devices: DummyData.devices, details: DummyData.details)
        #expect(!state.isScanning)
        #expect(state.devices.count == 3)
        #expect(state.details.count == 2)
    }

    @Test func toggleFlipsSetting() {
        var state = DummyData.initialState(route: .device(DummyData.mouseID))
        #expect(control(state, "smartshift.active") == .toggle(isOn: true))
        state.toggleItem("smartshift.active")
        #expect(control(state, "smartshift.active") == .toggle(isOn: false))
        state.toggleItem("smartshift.active")
        #expect(control(state, "smartshift.active") == .toggle(isOn: true))
    }

    @Test func toggleOnRootRouteIsNoOp() {
        var state = DummyData.initialState()
        state.toggleItem("smartshift.active")
        #expect(state == DummyData.initialState())
    }

    @Test func toggleWorksInGeneralRoute() {
        var state = DummyData.initialState(route: .general)
        state.toggleItem("general.launchAtLogin")
        #expect(control(state, "general.launchAtLogin") == .toggle(isOn: false))
    }

    @Test func sliderClampsToRange() {
        var state = DummyData.initialState(route: .device(DummyData.mouseID))
        state.setSlider("dpi", to: 99999)
        #expect(control(state, "dpi") == .slider(
            SliderSpec(value: 8000, range: 200 ... 8000, step: 50, unit: "DPI")
        ))
        state.setSlider("dpi", to: -10)
        #expect(control(state, "dpi") == .slider(
            SliderSpec(value: 200, range: 200 ... 8000, step: 50, unit: "DPI")
        ))
    }

    @Test func sliderFractionStaysNormalized() {
        let low = SliderSpec(value: 200, range: 200 ... 8000, step: 50)
        let mid = SliderSpec(value: 4100, range: 200 ... 8000, step: 50)
        let high = SliderSpec(value: 8000, range: 200 ... 8000, step: 50)
        #expect(low.fraction == 0)
        #expect(mid.fraction > 0.49 && mid.fraction < 0.51)
        #expect(high.fraction == 1)
    }

    @Test func sliderDisplayValueUsesUnitRules() {
        #expect(SliderSpec(value: 1000, range: 200 ... 8000, step: 50, unit: "DPI")
            .displayValue == "1000 DPI")
        #expect(SliderSpec(value: 32, range: 1 ... 100, unit: "%").displayValue == "32%")
        #expect(SliderSpec(value: 2.5, range: 0 ... 5, step: 0.5, unit: "").displayValue == "2.5")
    }

    @Test func sliderDisplayValueHandlesFineSteps() {
        // 0.01 steps used to round to one decimal and show "0.9".
        #expect(SliderSpec(value: 0.92, range: 0.80 ... 0.98, step: 0.01)
            .displayValue == "0.92")
        #expect(SliderSpec(value: 0.98, range: 0.80 ... 0.98, step: 0.01)
            .displayValue == "0.98")
        // Multipliers attach directly, units get one space.
        #expect(SliderSpec(value: 3, range: 1 ... 10, step: 0.5, unit: "x")
            .displayValue == "3.0x")
        #expect(SliderSpec(value: 120, range: 20 ... 240, step: 1, unit: "ms")
            .displayValue == "120 ms")
    }

    @Test func finishScanFallsBackToRootWhenDeviceDisappears() {
        var state = DummyData.initialState(route: .device(DummyData.mouseID))
        let devices = DummyData.devices.filter { $0.id != DummyData.mouseID }
        let details = DummyData.details.filter { $0.key != DummyData.mouseID }

        state.finishScan(devices: devices, details: details)

        #expect(state.route == .root)
    }

    @Test func pickerClampsInvalidIndex() {
        var keyboard = DummyData.initialState(route: .device(DummyData.keyboardID))
        keyboard.selectOption("backlight.enabled", index: 99)
        // Not a picker: stays a toggle.
        #expect(control(keyboard, "backlight.enabled") == .toggle(isOn: true))

        var mouse = DummyData.initialState(route: .device(DummyData.mouseID))
        mouse.selectOption("smartshift.wheel_mode", index: 99)
        #expect(control(mouse, "smartshift.wheel_mode") == .picker(
            options: ["Ratchet", "Free Spin"],
            selectedIndex: 1
        ))

        mouse.selectOption("smartshift.wheel_mode", index: -3)
        #expect(control(mouse, "smartshift.wheel_mode") == .picker(
            options: ["Ratchet", "Free Spin"],
            selectedIndex: 0
        ))
    }

    @Test func pickerSelectsValidIndex() {
        var state = DummyData.initialState(route: .device(DummyData.mouseID))
        state.selectOption("smartshift.wheel_mode", index: 1)
        #expect(control(state, "smartshift.wheel_mode") == .picker(
            options: ["Ratchet", "Free Spin"],
            selectedIndex: 1
        ))
    }

    @Test func selfCheckPayloadIsValidJSON() throws {
        let data = try #require(SelfCheck.payload().data(using: .utf8))
        let report = try JSONDecoder().decode(SelfCheckReport.self, from: data)
        #expect(report.status == "ok")
        #expect(report.devices == 3)
        #expect(report.route == "root")
        #expect(report == SelfCheck.report())
    }
}

struct PopoverSizingTests {
    @Test func clampsTallContentToViewport() {
        #expect(PopoverSizing.viewportHeight(measured: 860, maxViewport: 560) == 560)
    }

    @Test func keepsContentShorterThanViewport() {
        #expect(PopoverSizing.viewportHeight(measured: 184, maxViewport: 560) == 184)
    }

    @Test func fallsBackBeforeFirstLayoutPass() {
        #expect(PopoverSizing.viewportHeight(measured: 0, maxViewport: 560) == PopoverSizing
            .fallbackViewport)
        #expect(PopoverSizing.viewportHeight(measured: 1, maxViewport: 560) == PopoverSizing
            .fallbackViewport)
    }

    @Test func maxViewportLeavesRoomForMenuBar() {
        #expect(PopoverSizing.maxViewport(screenHeight: 1080) == 940)
    }

    @Test func maxViewportHasFloorForTinyScreens() {
        #expect(PopoverSizing.maxViewport(screenHeight: 300) == PopoverSizing.minimumViewport)
    }
}

struct AppSystemSettingsTests {
    @Test func generalToggleTakesSystemValue() {
        var state = DummyData.initialState(route: .general)
        state.setGeneralToggle("general.launchAtLogin", to: false)
        #expect(state.settingValue("general.launchAtLogin") == .bool(false))
    }

    @Test func finishScanCarriesWarning() {
        var state = DummyData.emptyState()
        state.beginScan()
        state.finishScan(
            devices: [],
            details: [:],
            warning: "Input Monitoring permission required"
        )
        #expect(state.warning == "Input Monitoring permission required")
        #expect(!state.isScanning)
    }
}
