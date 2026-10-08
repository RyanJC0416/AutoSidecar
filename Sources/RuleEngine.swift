import Foundation

enum RuleEngine {
    /// Connect scenes fire when the recorded object appears. Disconnect scenes fire when it leaves.
    static func firedRules(rules: [Rule], previous: WorldSnapshot, current: WorldSnapshot) -> [Rule] {
        rules.filter { rule in
            guard rule.enabled else { return false }
            let before = previous.ids(for: rule.scene)
            let after = current.ids(for: rule.scene)
            if rule.scene.firesOnAppearance {
                return after.contains(rule.targetID) && !before.contains(rule.targetID)
            }
            return before.contains(rule.targetID) && !after.contains(rule.targetID)
        }
    }
}
