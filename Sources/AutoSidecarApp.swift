import AppKit
import SwiftUI

@main
struct AutoSidecarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: AppModel

    init() {
        if CommandLine.arguments.contains("--dump") {
            Diagnostics.dump()
            exit(0)
        }
        let bundleID = Bundle.main.bundleIdentifier
        if let bundleID {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !others.isEmpty {
                exit(0)
            }
        }
        _model = StateObject(wrappedValue: AppModel())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(model)
        } label: {
            Image(systemName: model.sidecarDevices.contains(where: \.connected) ? "ipad.landscape" : "ipad")
        }
        .menuBarExtraStyle(.menu)

        Window("自动随航", id: "settings") {
            SettingsView()
                .environmentObject(model)
        }
        .defaultLaunchBehavior(CommandLine.arguments.contains("--show") ? .presented : .suppressed)
        .defaultSize(width: 860, height: 640)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("menu-bar")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
