import Foundation

struct UpdateCheck {
    var hasUpdate: Bool
    var latestVersion: String
    var downloadURL: URL?
    var message: String
}

enum UpdateManager {
    static let repo = "RyanJC0416/AutoSidecar"
    static let assetName = "AutoSidecar.app.zip"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func check() async -> UpdateCheck {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AutoSidecar/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 {
                return UpdateCheck(hasUpdate: false, latestVersion: currentVersion, downloadURL: nil, message: "还没有可安装的 Release。")
            }
            guard (200..<300).contains(status) else {
                return UpdateCheck(hasUpdate: false, latestVersion: "", downloadURL: nil, message: "检查更新失败：HTTP \(status)")
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            guard isNewer(latest, than: currentVersion) else {
                return UpdateCheck(hasUpdate: false, latestVersion: latest, downloadURL: nil, message: "已是最新版本 \(currentVersion)")
            }
            guard let asset = release.assets.first(where: { $0.name == assetName }) else {
                return UpdateCheck(hasUpdate: true, latestVersion: latest, downloadURL: nil, message: "版本 \(latest) 的 Release 里没有 \(assetName)")
            }
            return UpdateCheck(hasUpdate: true, latestVersion: latest, downloadURL: asset.browserDownloadURL, message: "发现新版本 \(latest)")
        } catch {
            return UpdateCheck(hasUpdate: false, latestVersion: "", downloadURL: nil, message: "检查更新失败")
        }
    }

    static func downloadAndInstall(from assetURL: URL, version: String) async -> String? {
        if isTranslocated() {
            return "请先把自动随航拖进「应用程序」文件夹，再从那里打开后更新。"
        }
        guard let appPath = Bundle.main.bundleURL.path as String?, appPath.hasSuffix(".app") else {
            return "当前不是 App 包，无法原地更新。"
        }
        let fileManager = FileManager.default
        let updates = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AutoSidecar/updates", isDirectory: true)
        let temp = updates.appendingPathComponent("upd-\(UUID().uuidString)", isDirectory: true)
        let extract = temp.appendingPathComponent("extracted", isDirectory: true)
        do {
            try fileManager.createDirectory(at: extract, withIntermediateDirectories: true)
            var request = URLRequest(url: assetURL, timeoutInterval: 120)
            request.setValue("AutoSidecar/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (downloaded, response) = try await URLSession.shared.download(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return "下载失败：HTTP \(http.statusCode)"
            }
            let archive = temp.appendingPathComponent("app.zip")
            try? fileManager.removeItem(at: archive)
            try fileManager.moveItem(at: downloaded, to: archive)
            try run("/usr/bin/unzip", ["-q", archive.path, "-d", extract.path])
            let newApp = extract.appendingPathComponent("AutoSidecar.app", isDirectory: true)
            guard fileManager.fileExists(atPath: newApp.path) else {
                return "更新包里没有 AutoSidecar.app"
            }
            try launchInstaller(newApp: newApp, tempDirectory: temp)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func launchInstaller(newApp: URL, tempDirectory: URL) throws {
        let current = Bundle.main.bundleURL.path
        let directory = (current as NSString).deletingLastPathComponent
        let scriptURL = tempDirectory.appendingPathComponent("install.zsh")
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/zsh
        set -e
        APP_PATH=\(quote(current))
        APP_DIR=\(quote(directory))
        NEW_APP=\(quote(newApp.path))
        TEMP_DIR=\(quote(tempDirectory.path))
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "$APP_PATH.old"
        mv "$APP_PATH" "$APP_PATH.old"
        if ! cp -R "$NEW_APP" "$APP_DIR/"; then
          mv "$APP_PATH.old" "$APP_PATH" || true
          exit 1
        fi
        xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
        open "$APP_PATH"
        rm -rf "$APP_PATH.old" "$TEMP_DIR"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        try process.run()
    }

    private static func run(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.command(path)
        }
    }

    private static func quote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func isTranslocated() -> Bool {
        let path = Bundle.main.bundleURL.path
        return path.contains("/AppTranslocation/")
            || (path.contains("/private/var/folders/") && path.contains("/T/"))
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private enum UpdateError: LocalizedError {
    case command(String)

    var errorDescription: String? {
        switch self {
        case .command(let name): return "\(name) 执行失败"
        }
    }
}
