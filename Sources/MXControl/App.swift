import MXControlHIDPP
import AppKit
import ServiceManagement
import SwiftUI

@main
struct MXControlApp: App {
    @NSApplicationDelegateAdaptor(AppVisibilityController.self) private var appVisibilityController
    @AppStorage(AppVisibilityPreferences.hideFromDockKey) private var hideFromDock = AppVisibilityPreferences.defaultHideFromDock

    /// Menu bar icon loaded from bundle Resources as a template image.
    private static let menuBarIcon: NSImage = {
        let img: NSImage
        if let url = Bundle.main.url(forResource: "logi-logo", withExtension: "png"),
           let loaded = NSImage(contentsOf: url) {
            img = loaded
        } else {
            // Fallback to SF Symbol if resource not found
            img = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "MXControl") ?? NSImage()
        }
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }()

    init() {
        AppVisibilityPreferences.registerDefaults()
        BatteryNotifier.setup()
        MicMuteEngine.shared.startDeviceMonitoring()
    }

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarInsertion) {
            MenuBarView()
                .environment(AppRuntime.shared.deviceManager)
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarInsertion: Binding<Bool> {
        Binding(
            get: { !hideFromDock },
            set: { hideFromDock = !$0 }
        )
    }
}

