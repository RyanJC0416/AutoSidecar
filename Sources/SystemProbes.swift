import CoreWLAN
import Foundation
import IOKit
import IOKit.ps
import SystemConfiguration

struct ProbeResult {
    var snapshot: WorldSnapshot
    var power: [DetectedObject]
    var volumes: [DetectedObject]
    var devices: [DetectedObject]
    var networks: [DetectedObject]
    var sidecar: [SidecarDeviceInfo]
}

enum SystemProbes {
    static func collect() -> ProbeResult {
        let power = powerSources()
        let volumes = mountedVolumes()
        let devices = usbDevices()
        let networks = connectedNetworks()
        let sidecar = SidecarController.read()
        var snapshot = WorldSnapshot()
        snapshot.power = Set(power.map(\.id))
        snapshot.volumes = Set(volumes.map(\.id))
        snapshot.devices = Set(devices.map(\.id))
        snapshot.networks = Set(networks.map(\.id))
        for device in sidecar where device.connected {
            switch device.transport {
            case .wifi: snapshot.sidecarWiFi.insert(device.id)
            case .wired: snapshot.sidecarWired.insert(device.id)
            case .unknown: break
            }
        }
        return ProbeResult(
            snapshot: snapshot,
            power: power,
            volumes: volumes,
            devices: devices,
            networks: networks,
            sidecar: sidecar
        )
    }

    static func powerSources() -> [DetectedObject] {
        guard let unmanaged = IOPSCopyExternalPowerAdapterDetails() else { return [] }
        let details = unmanaged.takeRetainedValue() as NSDictionary
        let watts = (details["Watts"] as? NSNumber)?.intValue ?? 0
        let wireless = (details["IsWireless"] as? NSNumber)?.intValue ?? 0
        let family = (details["FamilyCode"] as? NSNumber)?.stringValue ?? "na"
        let id = "power:\(family):\(wireless)"
        let name = wireless == 1 ? "无线电源 \(watts)W" : "有线电源 \(watts)W"
        return [DetectedObject(id: id, name: name, detail: "电源适配器")]
    }

    static func mountedVolumes() -> [DetectedObject] {
        let keys: [URLResourceKey] = [
            .volumeUUIDStringKey,
            .volumeNameKey,
            .volumeIsInternalKey,
            .volumeIsEjectableKey
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var objects: [DetectedObject] = []
        for url in urls {
            let path = url.path
            if path == "/" || path.hasPrefix("/System") { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let external = values.volumeIsInternal == false || values.volumeIsEjectable == true
            guard external, let uuid = values.volumeUUIDString, !uuid.isEmpty else { continue }
            let name = values.volumeName ?? url.lastPathComponent
            objects.append(DetectedObject(id: "volume:\(uuid)", name: name, detail: "外接磁盘"))
        }
        return objects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func usbDevices() -> [DetectedObject] {
        var objects: [DetectedObject] = []
        forEachService("IOUSBHostDevice") { service in
            guard let product = registryString(service, "USB Product Name") else { return }
            let lowered = product.lowercased()
            if lowered.contains("hub") || lowered.contains("billboard") || lowered.contains("bluetooth") {
                return
            }
            let vendorID = registryInt(service, "idVendor") ?? 0
            let productID = registryInt(service, "idProduct") ?? 0
            if vendorID == 1452 {
                let keep = lowered.contains("ipad") || lowered.contains("iphone") || lowered.contains("ipod")
                if !keep { return }
            }
            let vendor = registryString(service, "USB Vendor Name") ?? ""
            let serial = registryString(service, "USB Serial Number") ?? ""
            let unique = serial.isEmpty ? product : serial
            let name = vendor.isEmpty ? product : "\(vendor) \(product)"
            objects.append(DetectedObject(
                id: "usb:\(vendorID):\(productID):\(unique)",
                name: name,
                detail: serial.isEmpty ? "USB 设备" : "序列号 \(serial)"
            ))
        }
        var seen = Set<String>()
        return objects
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func connectedNetworks() -> [DetectedObject] {
        let wifiNames = Set((CWWiFiClient.shared().interfaces() ?? []).compactMap(\.interfaceName))
        var ssidByInterface: [String: String] = [:]
        for interface in CWWiFiClient.shared().interfaces() ?? [] {
            guard let name = interface.interfaceName, let ssid = interface.ssid(), !ssid.isEmpty else { continue }
            ssidByInterface[name] = ssid
        }

        guard let prefs = SCPreferencesCreate(nil, "AutoSidecar" as CFString, nil),
              let set = SCNetworkSetCopyCurrent(prefs) else {
            return []
        }
        let services = SCNetworkSetCopyServices(set) as? [SCNetworkService] ?? []
        guard let store = SCDynamicStoreCreate(nil, "AutoSidecar" as CFString, nil, nil) else { return [] }

        var objects: [DetectedObject] = []
        for service in services {
            guard let iface = SCNetworkServiceGetInterface(service),
                  let bsd = SCNetworkInterfaceGetBSDName(iface) as String?,
                  let serviceID = SCNetworkServiceGetServiceID(service) as String? else {
                continue
            }
            let key = "State:/Network/Service/\(serviceID)/IPv4" as CFString
            guard let ipv4 = SCDynamicStoreCopyValue(store, key) as? [String: Any],
                  let addresses = ipv4["Addresses"] as? [String],
                  let address = addresses.first,
                  !address.isEmpty else {
                continue
            }
            let router = (ipv4["Router"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let serviceName = (SCNetworkServiceGetName(service) as String?) ?? bsd
            let type = SCNetworkInterfaceGetInterfaceType(iface) as String?
            let isWiFi = wifiNames.contains(bsd) || type == (kSCNetworkInterfaceTypeIEEE80211 as String)

            if isWiFi {
                if let ssid = ssidByInterface[bsd] {
                    objects.append(DetectedObject(id: "wifi:\(ssid)", name: ssid, detail: "Wi-Fi · \(serviceName)"))
                } else if let router {
                    objects.append(DetectedObject(
                        id: "wifi-gw:\(router)",
                        name: "Wi-Fi 网关 \(router)",
                        detail: "系统没有返回 Wi-Fi 名称，当前用网关区分网络"
                    ))
                }
            } else if let router {
                objects.append(DetectedObject(
                    id: "ethernet:\(router)",
                    name: serviceName,
                    detail: "有线 · 网关 \(router)"
                ))
            } else {
                objects.append(DetectedObject(
                    id: "ethernet:\(bsd):\(address)",
                    name: serviceName,
                    detail: "有线 · \(address)"
                ))
            }
        }
        var seen = Set<String>()
        return objects
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func forEachService(_ className: String, _ body: (io_registry_entry_t) -> Void) {
        guard let matching = IOServiceMatching(className) else { return }
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            body(service)
            IOObjectRelease(service)
        }
    }

    private static func registryString(_ service: io_registry_entry_t, _ key: String) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func registryInt(_ service: io_registry_entry_t, _ key: String) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber else {
            return nil
        }
        return value.intValue
    }
}
