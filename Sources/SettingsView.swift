import AppKit
import SwiftUI

struct RuleDraft: Equatable {
    var ruleID: UUID?
    var enabled = true
    var scene: SceneKind = .powerConnected
    var targetID: String?
    var targetName = ""
    var action: ActionKind = .enableSidecar
    var sidecarID: String?
    var sidecarName = ""

    static func from(_ rule: Rule) -> RuleDraft {
        RuleDraft(
            ruleID: rule.id,
            enabled: rule.enabled,
            scene: rule.scene,
            targetID: rule.targetID,
            targetName: rule.targetName,
            action: rule.action,
            sidecarID: rule.sidecarDeviceID,
            sidecarName: rule.sidecarDeviceName
        )
    }

    func makeRule() -> Rule? {
        guard let targetID, let sidecarID, !targetName.isEmpty, !sidecarName.isEmpty else { return nil }
        return Rule(
            id: ruleID ?? UUID(),
            enabled: enabled,
            scene: scene,
            targetID: targetID,
            targetName: targetName,
            action: action,
            sidecarDeviceID: sidecarID,
            sidecarDeviceName: sidecarName
        )
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedID: UUID?
    @State private var draft = RuleDraft()
    @State private var creating = false
    @State private var pendingDelete: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                sidebar
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
                detail
                    .frame(minWidth: 420)
            }
            Divider()
            footer
        }
        .frame(minWidth: 780, minHeight: 560)
        .confirmationDialog("删除这条规则？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let pendingDelete {
                    model.deleteRule(pendingDelete)
                    if selectedID == pendingDelete {
                        selectedID = nil
                        creating = false
                    }
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
        .onAppear { AppWindows.showInDock() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.sidecarStatusLine)
                .font(.headline)
            Text(model.lastEvent.isEmpty ? "规则在记录的对象刚连上、刚断开，或随航刚切换连接方式时触发。" : model.lastEvent)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            if model.rules.isEmpty {
                Text("还没有规则")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.rules) { rule in
                            ruleRow(rule)
                        }
                    }
                    .padding(8)
                }
            }
            Divider()
            Button {
                creating = true
                selectedID = nil
                draft = RuleDraft()
            } label: {
                Label("添加规则", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .padding(12)
        }
    }

    private func ruleRow(_ rule: Rule) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { model.setRuleEnabled(rule.id, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            Button {
                creating = false
                selectedID = rule.id
                draft = RuleDraft.from(rule)
            } label: {
                Text(rule.summary)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                pendingDelete = rule.id
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selectedID == rule.id && !creating ? Color.accentColor.opacity(0.16) : Color.clear)
        )
    }

    @ViewBuilder
    private var detail: some View {
        if creating || selectedID != nil {
            editor
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("给随航加一条具体规则")
                    .font(.title2)
                Text("场景只能从当前已经检测到的对象里选。比如某一只电源、某一块硬盘、扩展坞、某个网络，或某一台 iPad。行为也要指定到这一台随航设备。")
                Text("单独去开会：场景选「断开电源」或「断开设备」，对象选现在这只适配器或扩展坞，行为选关闭随航，设备选这台 iPad。")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(creating ? "新规则" : "编辑规则")
                    .font(.title2)

                Picker("场景", selection: $draft.scene) {
                    ForEach(SceneKind.allCases) { scene in
                        Text(scene.title).tag(scene)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: draft.scene) { _, scene in
                    if scene == .networkConnected {
                        model.requestWiFiAccess()
                    }
                    let live = model.objects(for: scene)
                    if let targetID = draft.targetID, !live.contains(where: { $0.id == targetID }) {
                        draft.targetID = nil
                        draft.targetName = ""
                    }
                }

                objectSection(
                    title: "对象",
                    hint: model.emptyHint(for: draft.scene),
                    objects: sceneChoices,
                    selection: $draft.targetID
                )
                .onChange(of: draft.targetID) { _, id in
                    if let id, let match = sceneChoices.first(where: { $0.id == id }) {
                        draft.targetName = match.name
                    }
                }

                Picker("行为", selection: $draft.action) {
                    ForEach(ActionKind.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
                .pickerStyle(.menu)

                objectSection(
                    title: "随航设备",
                    hint: model.emptyHint(for: .sidecarWiFi),
                    objects: sidecarChoices,
                    selection: $draft.sidecarID
                )
                .onChange(of: draft.sidecarID) { _, id in
                    if let id, let match = sidecarChoices.first(where: { $0.id == id }) {
                        draft.sidecarName = match.name
                    }
                }

                Text(draft.scene.firesOnAppearance
                    ? "对象从没有变成有的那一下才会触发。它现在已经连着的话，要先断开再连上。"
                    : "对象从有变成没有的那一下才会触发。它现在还连着，要等它断开。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("保存规则") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                    Button("执行一次") {
                        guard let sidecarID = draft.sidecarID else { return }
                        model.runNow(action: draft.action, deviceID: sidecarID, deviceName: draft.sidecarName)
                    }
                    .disabled(draft.sidecarID == nil || draft.sidecarName.isEmpty)
                }
            }
            .padding(24)
        }
        .onAppear {
            if draft.scene == .networkConnected {
                model.requestWiFiAccess()
            }
        }
    }

    private var sceneChoices: [DetectedObject] {
        remembered(model.objects(for: draft.scene), id: draft.targetID, name: draft.targetName)
    }

    private var sidecarChoices: [DetectedObject] {
        let live = model.sidecarDevices.map {
            DetectedObject(id: $0.id, name: $0.name, detail: $0.linkTitle)
        }
        return remembered(live, id: draft.sidecarID, name: draft.sidecarName)
    }

    private func remembered(_ live: [DetectedObject], id: String?, name: String) -> [DetectedObject] {
        guard let id, !live.contains(where: { $0.id == id }) else { return live }
        return [DetectedObject(id: id, name: name.isEmpty ? id : name, detail: "当前未检测到，仍保留这条记录")] + live
    }

    private var canSave: Bool {
        guard let targetID = draft.targetID, let sidecarID = draft.sidecarID,
              !draft.targetName.isEmpty, !draft.sidecarName.isEmpty else {
            return false
        }
        if draft.ruleID == nil {
            let liveTarget = model.objects(for: draft.scene).contains { $0.id == targetID }
            let liveSidecar = model.sidecarDevices.contains { $0.id == sidecarID }
            return liveTarget && liveSidecar
        }
        return true
    }

    private func objectSection(title: String, hint: String, objects: [DetectedObject], selection: Binding<String?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            if objects.isEmpty {
                Text(hint)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            } else {
                List(objects, selection: selection) { object in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(object.name)
                        Text(object.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(object.id)
                    .padding(.vertical, 2)
                }
                .frame(height: 150)
            }
        }
    }

    private func save() {
        guard let rule = draft.makeRule() else { return }
        model.saveRule(rule)
        draft.ruleID = rule.id
        creating = false
        selectedID = rule.id
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Toggle("开机自启", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            Toggle("自动更新", isOn: Binding(
                get: { model.autoUpdate },
                set: { model.setAutoUpdate($0) }
            ))
            Spacer()
            if !model.updateStatus.isEmpty {
                Text(model.updateStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Button(model.updateBusy ? "正在更新…" : "检查更新") {
                model.checkForUpdates(manual: true)
            }
            .disabled(model.updateBusy)
            Text("版本 \(model.version)")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
