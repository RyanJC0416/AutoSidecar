import AppKit
import ObjectiveC
import SwiftUI

@main
struct AutoSidecarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: AppModel

    init() {
        FrameAutosaveBlock.install()
        WindowFrameLock.shared.prepare()
        if CommandLine.arguments.contains("--dump") {
            Diagnostics.dump()
            exit(0)
        }
        let bundleID = Bundle.main.bundleIdentifier
        if let bundleID {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if let existing = others.first {
                existing.activate(options: [.activateAllWindows])
                DistributedNotificationCenter.default().postNotificationName(
                    AppWindows.reopenName,
                    object: nil,
                    userInfo: nil,
                    deliverImmediately: true
                )
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
                .background(WindowOpener())
        }
        .menuBarExtraStyle(.menu)

        Window("自动随航", id: "settings") {
            SettingsView()
                .environmentObject(model)
        }
        .defaultLaunchBehavior(AppWindows.openAtLaunch ? .presented : .suppressed)
        .defaultSize(width: 860, height: 640)
        .windowResizability(.contentMinSize)
    }
}

enum AppWindows {
    static let reopenName = Notification.Name("com.ryanjc.autosidecar.open")
    static var openHandler: (() -> Void)?

    static var openAtLaunch: Bool {
        CommandLine.arguments.contains("--show") || !launchedAtLogin
    }

    private static var launchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        guard event.eventClass == kCoreEventClass, event.eventID == kAEOpenApplication else { return false }
        let properties = AEKeyword(0x70726474)
        let loginItem = AEKeyword(0x6C676974)
        guard let props = event.paramDescriptor(forKeyword: properties) else { return false }
        return props.paramDescriptor(forKeyword: loginItem)?.booleanValue == true
    }

    static func showInDock() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { bringOnScreen() }
    }

    static func hideDockIfNoWindow() {
        DispatchQueue.main.async {
            let open = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
            NSApp.setActivationPolicy(open ? .regular : .accessory)
        }
    }

    static func bringOnScreen() {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
        WindowFrameLock.shared.attach(window)
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
        if !onScreen, let screen = NSScreen.main ?? NSScreen.screens.first {
            let area = screen.visibleFrame
            let size = window.frame.size
            let origin = NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
            window.setFrameOrigin(origin)
        }
        window.makeKeyAndOrderFront(nil)
    }
}

/// SwiftUI names the settings window after its id, and AppKit then stores a separate
/// frame for each display. Dragging the window onto another screen restores that
/// display's old size. Keep one size for every screen instead.
private enum FrameAutosaveBlock {
    static func install() {
        let cls: AnyClass = NSWindow.self
        func swap(_ original: Selector, _ replacement: Selector) {
            guard let first = class_getInstanceMethod(cls, original),
                  let second = class_getInstanceMethod(cls, replacement) else { return }
            method_exchangeImplementations(first, second)
        }
        swap(#selector(NSWindow.setFrameAutosaveName(_:)), #selector(NSWindow.ignoreFrameAutosaveName(_:)))
        swap(#selector(NSWindow.constrainFrameRect(_:to:)), #selector(NSWindow.keepSizeWhenConstrainingFrame(_:to:)))
    }
}

extension NSWindow {
    @objc dynamic func ignoreFrameAutosaveName(_ name: String) -> Bool {
        ignoreFrameAutosaveName("")
    }

    @objc dynamic func keepSizeWhenConstrainingFrame(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        var rect = keepSizeWhenConstrainingFrame(frameRect, to: screen)
        rect.size = frameRect.size
        return rect
    }
}

final class WindowFrameLock: NSObject {
    static let shared = WindowFrameLock()
    private let defaultsKey = "settingsWindowSize"
    private var size: NSSize?
    private var screenKey = ""
    private var applying = false

    func prepare() {
        if UserDefaults.standard.string(forKey: defaultsKey) == nil,
           let legacy = UserDefaults.standard.string(forKey: "NSWindow Frame settings") {
            let parts = legacy.split(separator: " ")
            if parts.count >= 4 {
                UserDefaults.standard.set("\(parts[2]),\(parts[3])", forKey: defaultsKey)
            }
        }
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame settings")
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowChanged(_:)), name: NSWindow.didChangeScreenNotification, object: nil)
        center.addObserver(self, selector: #selector(windowChanged(_:)), name: NSWindow.didResizeNotification, object: nil)
        center.addObserver(self, selector: #selector(windowChanged(_:)), name: NSWindow.didChangeBackingPropertiesNotification, object: nil)
        center.addObserver(self, selector: #selector(userResized(_:)), name: NSWindow.didEndLiveResizeNotification, object: nil)
    }

    func attach(_ window: NSWindow) {
        guard window.canBecomeMain, window.frame.width > 50 else { return }
        if size == nil {
            size = storedSize() ?? window.frame.size
            apply(size!, to: window)
        }
        screenKey = key(of: window)
    }

    @objc private func userResized(_ note: Notification) {
        guard let window = settingsWindow(note), !applying else { return }
        remember(window.frame.size)
    }

    @objc private func windowChanged(_ note: Notification) {
        guard let window = settingsWindow(note), !applying else { return }
        let current = key(of: window)
        if screenKey.isEmpty {
            screenKey = current
            return
        }
        if current != screenKey {
            let previous = screenKey
            screenKey = current
            guard !previous.isEmpty, let size else { return }
            apply(size, to: window)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, let size = self.size, !window.inLiveResize else { return }
                self.apply(size, to: window)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak window] in
                guard let self, let window, let size = self.size, !window.inLiveResize else { return }
                self.apply(size, to: window)
            }
            return
        }
        if window.inLiveResize {
            remember(window.frame.size)
        }
    }

    private func apply(_ size: NSSize, to window: NSWindow) {
        let now = window.frame.size
        guard abs(now.width - size.width) > 1 || abs(now.height - size.height) > 1 else { return }
        applying = true
        var frame = window.frame
        frame.size = size
        window.setFrame(frame, display: true, animate: false)
        applying = false
    }

    private func remember(_ size: NSSize) {
        guard size.width > 50, size.height > 50 else { return }
        self.size = size
        UserDefaults.standard.set("\(size.width),\(size.height)", forKey: defaultsKey)
    }

    private func storedSize() -> NSSize? {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey) else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 50, parts[1] > 50 else { return nil }
        return NSSize(width: parts[0], height: parts[1])
    }

    private func settingsWindow(_ note: Notification) -> NSWindow? {
        guard let window = note.object as? NSWindow, window.canBecomeMain, window.frame.width > 50 else { return nil }
        return window
    }

    private func key(of window: NSWindow) -> String {
        guard let frame = window.screen?.frame else { return "" }
        return "\(frame.origin.x),\(frame.origin.y),\(frame.size.width),\(frame.size.height)"
    }
}

private struct WindowOpener: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                AppWindows.openHandler = { openWindow(id: "settings") }
            }
            .onReceive(DistributedNotificationCenter.default().publisher(for: AppWindows.reopenName)) { _ in
                AppWindows.showInDock()
                openWindow(id: "settings")
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(AppWindows.openAtLaunch ? .regular : .accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("menu-bar")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidClose(_:)),
            name: Notification.Name("NSWindowDidCloseNotification"),
            object: nil
        )
    }

    @objc private func windowDidClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.canBecomeMain else { return }
        AppWindows.hideDockIfNoWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppWindows.showInDock()
        AppWindows.openHandler?()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
