import Foundation

public enum CodexPlan: String, Equatable, Sendable {
    case go
    case plus
    case pro5x
    case pro20x

    public init?(serverValue: String?) {
        switch serverValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "go":
            self = .go
        case "plus":
            self = .plus
        case "prolite", "pro_lite", "pro-lite", "pro lite":
            self = .pro5x
        case "pro":
            self = .pro20x
        default:
            return nil
        }
    }

    public var displayName: String {
        switch self {
        case .go: "Go"
        case .plus: "Plus"
        case .pro5x: "Pro 5x"
        case .pro20x: "Pro 20x"
        }
    }
}
