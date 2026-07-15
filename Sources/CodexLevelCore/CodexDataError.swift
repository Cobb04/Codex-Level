import Foundation

public enum CodexDataError: Error, Equatable, Sendable {
    case notLoggedIn
    case authenticationExpired
    case networkFailure
    case responseFormatChanged
    case codexNotFound
    case appServerTimeout
    case appServerFailure
}

extension CodexDataError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            "Please sign in to Codex first."
        case .authenticationExpired:
            "Codex authentication has expired. Please sign in again."
        case .networkFailure:
            "The Codex data request failed."
        case .responseFormatChanged:
            "Codex returned data in an unsupported format."
        case .codexNotFound:
            "The Codex executable was not found."
        case .appServerTimeout:
            "Codex app-server timed out."
        case .appServerFailure:
            "Codex app-server failed."
        }
    }
}
