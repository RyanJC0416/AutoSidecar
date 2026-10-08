import Foundation

enum SceneKind: String, Codable, CaseIterable, Identifiable {
    case powerConnected
    case powerDisconnected
    case volumeMounted
    case volumeUnmounted
    case deviceConnected
    case deviceDisconnected
    case networkConnected
    case networkDisconnected
    case sidecarWiFi
    case sidecarWired

    var id: String { rawValue }

    var title: String {
        switch self {
        case .powerConnected: return "连接电源"
        case .powerDisconnected: return "断开电源"
        case .volumeMounted: return "连接移动硬盘"
        case .volumeUnmounted: return "断开移动硬盘"
        case .deviceConnected: return "连接设备"
        case .deviceDisconnected: return "断开设备"
        case .networkConnected: return "连接网络"
        case .networkDisconnected: return "断开网络"
        case .sidecarWiFi: return "随航切换到 Wi-Fi"
        case .sidecarWired: return "随航切换到有线"
        }
    }

    /// Disconnect scenes fire when the recorded object leaves. Everything else fires when it appears.
    var firesOnAppearance: Bool {
        switch self {
        case .powerDisconnected, .volumeUnmounted, .deviceDisconnected, .networkDisconnected:
            return false
        case .powerConnected, .volumeMounted, .deviceConnected, .networkConnected, .sidecarWiFi, .sidecarWired:
            return true
        }
    }

    var matchedSet: SceneKind {
        switch self {
        case .powerConnected, .powerDisconnected: return .powerConnected
        case .volumeMounted, .volumeUnmounted: return .volumeMounted
        case .deviceConnected, .deviceDisconnected: return .deviceConnected
        case .networkConnected, .networkDisconnected: return .networkConnected
        case .sidecarWiFi: return .sidecarWiFi
        case .sidecarWired: return .sidecarWired
        }
    }
}

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case enableSidecar
    case disableSidecar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .enableSidecar: return "启用随航"
        case .disableSidecar: return "关闭随航"
        }
    }
}

enum SidecarTransport: String, Codable, Equatable {
    case wired
    case wifi
    case unknown

    var title: String {
        switch self {
        case .wired: return "有线"
        case .wifi: return "Wi-Fi"
        case .unknown: return "未知"
        }
    }

    static func classify(_ raw: Int) -> SidecarTransport {
        switch raw {
        case 1: return .wired
        case 2: return .wifi
        default: return .unknown
        }
    }
}

struct DetectedObject: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var detail: String
}

struct SidecarDeviceInfo: Identifiable, Equatable {
    var id: String
    var name: String
    var connected: Bool
    var transportRaw: Int
    var transport: SidecarTransport

    var linkTitle: String {
        guard connected else { return "未开启" }
        if transport == .unknown { return "未知传输 \(transportRaw)" }
        return transport.title
    }
}

struct Rule: Identifiable, Codable, Equatable {
    var id: UUID
    var enabled: Bool
    var scene: SceneKind
    var targetID: String
    var targetName: String
    var action: ActionKind
    var sidecarDeviceID: String
    var sidecarDeviceName: String

    var summary: String {
        "\(scene.title)「\(targetName)」→ \(action.title)「\(sidecarDeviceName)」"
    }
}

struct AppConfig: Codable, Equatable {
    var rules: [Rule] = []
    var launchAtLogin: Bool = false
    var autoUpdate: Bool = false
}

struct WorldSnapshot: Codable, Equatable {
    var power: Set<String> = []
    var volumes: Set<String> = []
    var devices: Set<String> = []
    var networks: Set<String> = []
    var sidecarWiFi: Set<String> = []
    var sidecarWired: Set<String> = []

    func ids(for scene: SceneKind) -> Set<String> {
        switch scene.matchedSet {
        case .powerConnected: return power
        case .volumeMounted: return volumes
        case .deviceConnected: return devices
        case .networkConnected: return networks
        case .sidecarWiFi: return sidecarWiFi
        case .sidecarWired: return sidecarWired
        default: return []
        }
    }
}

struct PendingAction: Equatable {
    var action: ActionKind
    var deviceID: String
    var deviceName: String
}
