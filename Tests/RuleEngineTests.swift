import Foundation

@main
struct RuleEngineTests {
    static func main() {
        testAppearingTargetFires()
        testAlreadyPresentDoesNotFire()
        testDisabledRuleDoesNotFire()
        testOtherSceneDoesNotFire()
        testWiFiAndWiredAreSeparate()
        testDisappearanceFires()
        testVersionCompare()
        print("ok")
    }

    static func testAppearingTargetFires() {
        let rule = sample(scene: .volumeMounted, target: "volume:disk")
        let previous = WorldSnapshot()
        var current = WorldSnapshot()
        current.volumes = ["volume:disk"]
        let fired = RuleEngine.firedRules(rules: [rule], previous: previous, current: current)
        expect(fired.map(\.id) == [rule.id], "volume appear")
    }

    static func testAlreadyPresentDoesNotFire() {
        let rule = sample(scene: .powerConnected, target: "power:1")
        var snapshot = WorldSnapshot()
        snapshot.power = ["power:1"]
        let fired = RuleEngine.firedRules(rules: [rule], previous: snapshot, current: snapshot)
        expect(fired.isEmpty, "already present")
    }

    static func testDisabledRuleDoesNotFire() {
        var rule = sample(scene: .deviceConnected, target: "usb:1")
        rule.enabled = false
        var current = WorldSnapshot()
        current.devices = ["usb:1"]
        let fired = RuleEngine.firedRules(rules: [rule], previous: WorldSnapshot(), current: current)
        expect(fired.isEmpty, "disabled")
    }

    static func testOtherSceneDoesNotFire() {
        let rule = sample(scene: .networkConnected, target: "wifi:office")
        var current = WorldSnapshot()
        current.volumes = ["wifi:office"]
        let fired = RuleEngine.firedRules(rules: [rule], previous: WorldSnapshot(), current: current)
        expect(fired.isEmpty, "wrong scene")
    }

    static func testWiFiAndWiredAreSeparate() {
        let wifi = sample(scene: .sidecarWiFi, target: "ipad")
        let wired = sample(scene: .sidecarWired, target: "ipad")
        var current = WorldSnapshot()
        current.sidecarWiFi = ["ipad"]
        let fired = RuleEngine.firedRules(rules: [wifi, wired], previous: WorldSnapshot(), current: current)
        expect(fired.map(\.id) == [wifi.id], "only wifi")
    }

    static func testDisappearanceFires() {
        let rule = sample(scene: .powerDisconnected, target: "power:1")
        var previous = WorldSnapshot()
        previous.power = ["power:1"]
        let fired = RuleEngine.firedRules(rules: [rule], previous: previous, current: WorldSnapshot())
        expect(fired.map(\.id) == [rule.id], "power disconnect")
        let stillThere = RuleEngine.firedRules(rules: [rule], previous: previous, current: previous)
        expect(stillThere.isEmpty, "power still connected")
    }

    static func testVersionCompare() {
        expect(UpdateManager.isNewer("1.0.1", than: "1.0.0"), "patch")
        expect(!UpdateManager.isNewer("1.0.0", than: "1.0.0"), "same")
        expect(!UpdateManager.isNewer("1.2", than: "1.2.1"), "shorter older")
        expect(UpdateManager.isNewer("2", than: "1.9.9"), "major")
    }

    static func sample(scene: SceneKind, target: String) -> Rule {
        Rule(
            id: UUID(),
            enabled: true,
            scene: scene,
            targetID: target,
            targetName: target,
            action: .disableSidecar,
            sidecarDeviceID: "ipad",
            sidecarDeviceName: "iPad"
        )
    }

    static func expect(_ condition: Bool, _ name: String) {
        if !condition {
            fputs("FAIL \(name)\n", stderr)
            exit(1)
        }
    }
}
