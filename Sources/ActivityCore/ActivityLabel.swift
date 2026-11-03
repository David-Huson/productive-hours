import Foundation

public enum ActivityLabel {
    /// History and exports should reflect how the interval was classified, not re-match blindly.
    public static func label(for source: Source, rules: [ClassificationRule]) -> String {
        if let ruleID = source.ruleID, let rule = rules.first(where: { $0.id == ruleID }) {
            switch rule.kind {
            case .exactHost, .domain, .subdomains:
                return rule.label
            case .app where source.host == nil:
                return rule.label
            case .app:
                break
            }
        }
        if let host = source.host, !host.isEmpty { return host }
        if let ruleID = source.ruleID, let rule = rules.first(where: { $0.id == ruleID }) {
            return rule.label
        }
        let resolved = RuleEvaluator.resolve(app: source.app, host: source.host, rules: rules)
        if let ruleID = resolved.ruleID, let rule = rules.first(where: { $0.id == ruleID }) {
            return rule.label
        }
        return source.app.isEmpty ? "Unknown source" : source.app
    }
}
