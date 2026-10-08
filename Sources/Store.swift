import Foundation

enum Store {
    private static var directory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AutoSidecar", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var configURL: URL { directory.appendingPathComponent("config.json") }
    private static var snapshotURL: URL { directory.appendingPathComponent("snapshot.json") }

    static func loadConfig() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL) else { return AppConfig() }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            let bad = directory.appendingPathComponent("config.bad.json")
            try? FileManager.default.removeItem(at: bad)
            try? FileManager.default.moveItem(at: configURL, to: bad)
            return AppConfig()
        }
    }

    static func saveConfig(_ config: AppConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    static func loadSnapshot() -> WorldSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder().decode(WorldSnapshot.self, from: data)
    }

    static func saveSnapshot(_ snapshot: WorldSnapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: snapshotURL, options: .atomic)
    }
}
