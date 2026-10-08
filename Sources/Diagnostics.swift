import Foundation

enum Diagnostics {
    static func dump() {
        let result = SystemProbes.collect()
        print("version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
        print("== power ==")
        printObjects(result.power)
        print("== volumes ==")
        printObjects(result.volumes)
        print("== devices ==")
        printObjects(result.devices)
        print("== networks ==")
        printObjects(result.networks)
        print("== sidecar ==")
        if result.sidecar.isEmpty {
            print("(none)")
        }
        for device in result.sidecar {
            print("\(device.name) id=\(device.id) connected=\(device.connected) transport=\(device.transportRaw) \(device.linkTitle)")
        }
    }

    private static func printObjects(_ objects: [DetectedObject]) {
        if objects.isEmpty { print("(none)") }
        for object in objects {
            print("\(object.name) | \(object.detail) | \(object.id)")
        }
    }
}
