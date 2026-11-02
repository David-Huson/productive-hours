/// Productivity and input activity are independent dimensions.
public enum ProductivityClass: String, Codable, CaseIterable, Sendable {
    case productive, unproductive, undefined, ignored
}

public struct ActivityClassification: Equatable, Sendable {
    public let productivity: ProductivityClass
    public let activity: ActivityState

    public init(productivity: ProductivityClass = .undefined, activity: ActivityState) {
        self.productivity = productivity
        self.activity = activity
    }

    /// Eligibility only. Interval duration and persistence belong to the accounting engine.
    public var creditsProductiveTime: Bool {
        productivity == .productive && (activity == .active || activity == .passive)
    }
}
