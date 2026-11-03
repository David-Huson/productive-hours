import Foundation

public enum MenuBarActivityIndicator: String, Equatable, Sendable {
    case active, passive, inactive, unproductive, hidden
}

public enum MenuBarActivityIndicatorPolicy {
    public static func resolve(
        running: Bool,
        hasError: Bool,
        productivity: ProductivityClass,
        activity: ActivityState
    ) -> MenuBarActivityIndicator {
        guard running, !hasError else { return .hidden }
        if productivity == .unproductive { return .unproductive }
        switch activity {
        case .active: return .active
        case .passive: return .passive
        case .inactive: return .inactive
        case .unknown: return .hidden
        }
    }
}
