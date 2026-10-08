import AppKit
import SwiftUI

struct MenuContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.sidecarStatusLine)
        Text("启用规则 \(model.enabledRuleCount)/\(model.rules.count)")
        if !model.lastEvent.isEmpty {
            Text(model.lastEvent)
        }
        if !model.updateStatus.isEmpty {
            Text(model.updateStatus)
        }

        Divider()

        Button("设置…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button(model.updateBusy ? "正在更新…" : "检查更新") {
            model.checkForUpdates(manual: true)
        }
        .disabled(model.updateBusy)

        Divider()

        Button("退出自动随航") {
            NSApp.terminate(nil)
        }
    }
}
