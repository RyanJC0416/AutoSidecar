import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var rules: [Rule] = []
    @Published var launchAtLogin = false
    @Published var autoUpdate = false
    @Published var power: [DetectedObject] = []
    @Published var volumes: [DetectedObject] = []
    @Published var devices: [DetectedObject] = []
    @Published var networks: [DetectedObject] = []
    @Published var sidecarDevices: [SidecarDeviceInfo] = []
    @Published var sidecarStatusLine = "正在读取随航状态…"
    @Published var lastEvent = ""
    @Published var updateStatus = ""
    @Published var updateBusy = false

    private var previous: WorldSnapshot?
    private var seeded = false
    private var timer: Timer?
    private var queue: [PendingAction] = []
    private var actionRunning = false
    private var autoCheckStarted = false
    private let location = LocationAccess()

    static weak var shared: AppModel?

    var version: String { UpdateManager.currentVersion }
    var enabledRuleCount: Int { rules.filter(\.enabled).count }

    init() {
        AppModel.shared = self
        let config = Store.loadConfig()
        rules = config.rules
        launchAtLogin = config.launchAtLogin
        autoUpdate = config.autoUpdate
        LoginItemManager.sync(fromLaunchAtLogin: launchAtLogin)
        location.onChange = { [weak self] in
            Task { @MainActor in self?.tick() }
        }
        start()
    }

    func objects(for scene: SceneKind) -> [DetectedObject] {
        switch scene.matchedSet {
        case .powerConnected: return power
        case .volumeMounted: return volumes
        case .deviceConnected: return devices
        case .networkConnected: return networks
        case .sidecarWiFi, .sidecarWired:
            return sidecarDevices.map {
                DetectedObject(id: $0.id, name: $0.name, detail: $0.linkTitle)
            }
        default: return []
        }
    }

    func emptyHint(for scene: SceneKind) -> String {
        switch scene.matchedSet {
        case .powerConnected: return "接上电源适配器后，这里会出现这一只适配器。"
        case .volumeMounted: return "插上移动硬盘后，这里会出现那一块盘。"
        case .deviceConnected: return "接上扩展坞或其他 USB 设备后，这里会出现那一台设备。"
        case .networkConnected: return "连上 Wi-Fi、网线，或 iPad 的 USB 网络接口后，这里会出现这个网络。"
        case .sidecarWiFi, .sidecarWired: return "打开 iPad，并和这台 Mac 使用同一个 Apple 账号，随航设备会出现在这里。"
        default: return ""
        }
    }

    func requestWiFiAccess() {
        location.request()
    }

    func saveRule(_ rule: Rule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        persistConfig()
    }

    func deleteRule(_ id: UUID) {
        rules.removeAll { $0.id == id }
        persistConfig()
    }

    func setRuleEnabled(_ id: UUID, _ enabled: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].enabled = enabled
        persistConfig()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
            launchAtLogin = enabled
            persistConfig()
            lastEvent = enabled ? "已打开开机自启" : "已关闭开机自启"
        } catch {
            launchAtLogin = LoginItemManager.isEnabled
            lastEvent = "开机自启没有改成：\(error.localizedDescription)"
        }
    }

    func setAutoUpdate(_ enabled: Bool) {
        autoUpdate = enabled
        persistConfig()
        if enabled {
            checkForUpdates(manual: false)
        }
    }

    func runNow(action: ActionKind, deviceID: String, deviceName: String) {
        enqueue([PendingAction(action: action, deviceID: deviceID, deviceName: deviceName)])
    }

    func checkForUpdates(manual: Bool) {
        guard !updateBusy else { return }
        updateBusy = true
        if manual || updateStatus.isEmpty {
            updateStatus = "正在检查更新…"
        }
        Task {
            let result = await UpdateManager.check()
            await MainActor.run {
                self.apply(result, manual: manual)
            }
        }
    }

    private func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if autoUpdate {
            checkForUpdates(manual: false)
            autoCheckStarted = true
        }
    }

    private func tick() {
        let result = SystemProbes.collect()
        if power != result.power { power = result.power }
        if volumes != result.volumes { volumes = result.volumes }
        if devices != result.devices { devices = result.devices }
        if networks != result.networks { networks = result.networks }
        if sidecarDevices != result.sidecar { sidecarDevices = result.sidecar }
        sidecarStatusLine = statusLine(for: result.sidecar)

        if !seeded {
            seeded = true
            if let saved = Store.loadSnapshot() {
                previous = saved
            } else {
                previous = result.snapshot
                Store.saveSnapshot(result.snapshot)
                return
            }
        }
        guard let previous else { return }
        let fired = RuleEngine.firedRules(rules: rules, previous: previous, current: result.snapshot)
        if previous != result.snapshot {
            self.previous = result.snapshot
            Store.saveSnapshot(result.snapshot)
        }
        guard !fired.isEmpty else { return }
        enqueue(fired.map {
            PendingAction(action: $0.action, deviceID: $0.sidecarDeviceID, deviceName: $0.sidecarDeviceName)
        })
    }

    private func statusLine(for devices: [SidecarDeviceInfo]) -> String {
        let active = devices.filter(\.connected)
        if active.isEmpty { return "随航未开启" }
        return active.map { "随航已开启 · \($0.name) · \($0.linkTitle)" }.joined(separator: "    ")
    }

    private func enqueue(_ actions: [PendingAction]) {
        queue.append(contentsOf: actions)
        pump()
    }

    private func pump() {
        guard !actionRunning, !queue.isEmpty else { return }
        let item = queue.removeFirst()
        if let reason = skipReason(for: item) {
            lastEvent = reason
            pump()
            return
        }
        actionRunning = true
        lastEvent = "正在\(item.action.title)「\(item.deviceName)」…"
        SidecarController.perform(item.action, deviceID: item.deviceID, progress: { message in
            Task { @MainActor in
                AppModel.shared?.lastEvent = message
            }
        }) { error in
            Task { @MainActor in
                guard let model = AppModel.shared else { return }
                if let error {
                    model.lastEvent = "\(item.action.title)失败：\(error)"
                } else {
                    model.lastEvent = "已\(item.action.title)「\(item.deviceName)」"
                }
                model.actionRunning = false
                model.tick()
                model.pump()
            }
        }
    }

    private func skipReason(for item: PendingAction) -> String? {
        let device = sidecarDevices.first { $0.id.caseInsensitiveCompare(item.deviceID) == .orderedSame }
        switch item.action {
        case .enableSidecar where device?.connected == true:
            return "「\(item.deviceName)」的随航已经开着"
        case .disableSidecar where device?.connected != true:
            return "「\(item.deviceName)」的随航本来就没开"
        default:
            return nil
        }
    }

    private func apply(_ result: UpdateCheck, manual: Bool) {
        updateStatus = result.message
        guard result.hasUpdate, let url = result.downloadURL else {
            updateBusy = false
            if !manual, result.message == "检查更新失败" || result.message.hasPrefix("还没有") {
                updateStatus = ""
            }
            return
        }
        updateStatus = "正在下载 \(result.latestVersion)…"
        Task {
            let error = await UpdateManager.downloadAndInstall(from: url, version: result.latestVersion)
            await MainActor.run {
                if let error {
                    self.updateBusy = false
                    self.updateStatus = error
                } else {
                    self.updateStatus = "正在安装 \(result.latestVersion)…"
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func persistConfig() {
        Store.saveConfig(AppConfig(rules: rules, launchAtLogin: launchAtLogin, autoUpdate: autoUpdate))
    }
}
