import Darwin
import Foundation
import ObjectiveC

/// Talks to the private SidecarDisplayManager.
/// macOS does not publish a Sidecar API. `SidecarDisplayConfig.transport` is a private integer:
/// a live AirPlay Sidecar display (the iPad is not on the USB tree) reports 2, so 2 is Wi-Fi and 1 is wired.
enum SidecarController {
    private static let frameworkLoaded: Bool = {
        dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_NOW) != nil
    }()

    static func read() -> [SidecarDeviceInfo] {
        guard frameworkLoaded, let manager = sharedManager() else { return [] }
        let connectedIDs = Set(devices(manager, key: "connectedDevices").compactMap { identifier(of: $0)?.uppercased() })
        return knownDevices(manager).compactMap { device in
            guard let id = identifier(of: device) else { return nil }
            let offers = (device.value(forKey: "offersAdditionalDisplay") as? NSNumber)?.boolValue ?? true
            guard offers else { return nil }
            let name = (device.value(forKey: "name") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let connected = connectedIDs.contains(id.uppercased())
            let raw = connected ? transportRaw(of: device, manager: manager) : -1
            return SidecarDeviceInfo(
                id: id,
                name: (name?.isEmpty == false ? name! : "未命名设备"),
                connected: connected,
                transportRaw: raw,
                transport: connected ? SidecarTransport.classify(raw) : .unknown
            )
        }
    }

    static func perform(
        _ action: ActionKind,
        deviceID: String,
        progress: @escaping (String) -> Void = { _ in },
        completion: @escaping (String?) -> Void
    ) {
        guard frameworkLoaded, let manager = sharedManager() else {
            completion("这台系统读不到随航接口。")
            return
        }
        if action == .enableSidecar, SystemProbes.iPadWiredLinkIsRunning() {
            enableOverWire(manager, deviceID: deviceID, started: Date(), progress: progress, completion: completion)
            return
        }
        guard let device = device(manager, id: deviceID) else {
            completion("随航设备不在当前可检测列表里。")
            return
        }
        let selectorName = action == .enableSidecar
            ? "connectToDevice:completion:"
            : "disconnectFromDevice:completion:"
        call(manager, selectorName, device, completion)
    }

    /// `anri` comes up before the iPad advertises USB. Connecting in that gap makes
    /// Sidecar start an AWDL session, which dies immediately and shows “设备已断开”.
    /// `SidecarDevice.status` bit 24 is the USB flag from the rapport device flags.
    private static let usbReadyBit: UInt = 1 << 24
    private static let wireWaitLimit: TimeInterval = 75

    private static func enableOverWire(
        _ manager: NSObject,
        deviceID: String,
        started: Date,
        progress: @escaping (String) -> Void,
        completion: @escaping (String?) -> Void
    ) {
        guard SystemProbes.iPadWiredLinkIsRunning() else {
            completion("iPad 有线接口断开了，没有发起连接。")
            return
        }
        guard let device = device(manager, id: deviceID) else {
            completion("随航设备不在当前可检测列表里。")
            return
        }
        let status = (device.value(forKey: "status") as? NSNumber)?.uintValue ?? 0
        if status & usbReadyBit != 0 {
            connectWired(manager, device, completion)
            return
        }
        if Date().timeIntervalSince(started) > wireWaitLimit {
            completion("iPad 有线接口已经出现，但随航有线通道还没就绪，这次没有发起连接。")
            return
        }
        progress("正在等 iPad 有线通道…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            enableOverWire(manager, deviceID: deviceID, started: started, progress: progress, completion: completion)
        }
    }

    private static func device(_ manager: NSObject, id: String) -> NSObject? {
        knownDevices(manager).first {
            identifier(of: $0)?.caseInsensitiveCompare(id) == .orderedSame
        }
    }

    private static func connectWired(_ manager: NSObject, _ device: NSObject, _ completion: @escaping (String?) -> Void) {
        guard let configClass = NSClassFromString("SidecarDisplayConfig") as? NSObject.Type else {
            call(manager, "connectToDevice:completion:", device, completion)
            return
        }
        let config = configClass.init()
        config.setValue(1, forKey: "transport")
        let selector = NSSelectorFromString("connectToDevice:withConfig:completion:")
        guard let method = class_getInstanceMethod(type(of: manager), selector) else {
            call(manager, "connectToDevice:completion:", device, completion)
            return
        }
        typealias Function = @convention(c) (NSObject, Selector, NSObject, NSObject, @convention(block) (NSError?) -> Void) -> Void
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        let block: @convention(block) (NSError?) -> Void = { error in
            let message = error?.localizedDescription
            DispatchQueue.main.async { completion(message) }
        }
        function(manager, selector, device, config, block)
    }

    private static func sharedManager() -> NSObject? {
        guard let cls = NSClassFromString("SidecarDisplayManager") else { return nil }
        let selector = NSSelectorFromString("sharedManager")
        guard let method = class_getClassMethod(cls, selector) else { return nil }
        typealias Function = @convention(c) (AnyClass, Selector) -> NSObject?
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        return function(cls, selector)
    }

    private static func knownDevices(_ manager: NSObject) -> [NSObject] {
        var seen = Set<String>()
        var result: [NSObject] = []
        for device in devices(manager, key: "devices") + devices(manager, key: "connectedDevices") + allDevices() {
            guard let id = identifier(of: device)?.uppercased(), seen.insert(id).inserted else { continue }
            result.append(device)
        }
        return result
    }

    private static func allDevices() -> [NSObject] {
        guard let cls = NSClassFromString("SidecarDevice") else { return [] }
        let selector = NSSelectorFromString("allDevices")
        guard let method = class_getClassMethod(cls, selector) else { return [] }
        typealias Function = @convention(c) (AnyClass, Selector) -> AnyObject?
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        return objectList(function(cls, selector))
    }

    private static func devices(_ manager: NSObject, key: String) -> [NSObject] {
        let selector = NSSelectorFromString(key)
        guard manager.responds(to: selector) else { return [] }
        return objectList(manager.perform(selector)?.takeUnretainedValue())
    }

    private static func objectList(_ value: Any?) -> [NSObject] {
        if let list = value as? [NSObject] { return list }
        if let list = value as? NSArray { return list.compactMap { $0 as? NSObject } }
        return []
    }

    private static func identifier(of device: NSObject) -> String? {
        if let uuid = device.value(forKey: "identifier") as? UUID {
            return uuid.uuidString
        }
        if let uuid = device.value(forKey: "identifier") as? NSUUID {
            return uuid.uuidString
        }
        return nil
    }

    private static func transportRaw(of device: NSObject, manager: NSObject) -> Int {
        let selector = NSSelectorFromString("configForDevice:")
        guard let method = class_getInstanceMethod(type(of: manager), selector) else { return -1 }
        typealias ConfigFunction = @convention(c) (NSObject, Selector, NSObject) -> NSObject?
        let configFunction = unsafeBitCast(method_getImplementation(method), to: ConfigFunction.self)
        guard let config = configFunction(manager, selector, device) else { return -1 }
        let transportSelector = NSSelectorFromString("transport")
        guard let transportMethod = class_getInstanceMethod(type(of: config), transportSelector) else { return -1 }
        typealias TransportFunction = @convention(c) (NSObject, Selector) -> Int
        let transportFunction = unsafeBitCast(method_getImplementation(transportMethod), to: TransportFunction.self)
        return transportFunction(config, transportSelector)
    }

    private static func call(_ manager: NSObject, _ name: String, _ device: NSObject, _ completion: @escaping (String?) -> Void) {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(type(of: manager), selector) else {
            completion("系统没有 \(name)。")
            return
        }
        typealias Function = @convention(c) (NSObject, Selector, NSObject, @convention(block) (NSError?) -> Void) -> Void
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        let block: @convention(block) (NSError?) -> Void = { error in
            let message = error?.localizedDescription
            DispatchQueue.main.async {
                completion(message)
            }
        }
        function(manager, selector, device, block)
    }
}
