import Foundation

/// OAuth usage path adapted from CodexBar's MIT-licensed Codex provider.
public struct CodexOAuthUsageClient: Sendable {
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        self.session = URLSession(
            configuration: configuration,
            delegate: CodexProfileRedirectDelegate(),
            delegateQueue: nil)
    }

    public init(session: URLSession) {
        self.session = session
    }

    public func readWeeklyRateLimit(credentials: CodexCredentials) async throws -> WeeklyRateLimit {
        var request = URLRequest(
            url: Self.usageURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexLevel", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CodexDataError.networkFailure
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexDataError.networkFailure
        }
        switch httpResponse.statusCode {
        case 200 ... 299:
            break
        case 401, 403:
            throw CodexDataError.authenticationExpired
        default:
            throw CodexDataError.networkFailure
        }

        struct UsageResponse: Decodable {
            struct RateLimit: Decodable {
                struct Window: Decodable {
                    let usedPercent: Double
                    let resetAt: TimeInterval
                    let limitWindowSeconds: Int

                    enum CodingKeys: String, CodingKey {
                        case usedPercent = "used_percent"
                        case resetAt = "reset_at"
                        case limitWindowSeconds = "limit_window_seconds"
                    }
                }

                let primaryWindow: Window?
                let secondaryWindow: Window?

                enum CodingKeys: String, CodingKey {
                    case primaryWindow = "primary_window"
                    case secondaryWindow = "secondary_window"
                }
            }

            let rateLimit: RateLimit?
            let planType: String?

            enum CodingKeys: String, CodingKey {
                case rateLimit = "rate_limit"
                case planType = "plan_type"
            }
        }

        guard let usage = try? JSONDecoder().decode(UsageResponse.self, from: data),
              let window = usage.rateLimit?.secondaryWindow ?? usage.rateLimit?.primaryWindow,
              window.usedPercent.isFinite,
              (0 ... 100).contains(window.usedPercent),
              window.limitWindowSeconds > 0,
              window.resetAt > 0
        else {
            throw CodexDataError.responseFormatChanged
        }

        return WeeklyRateLimit(
            usedPercent: window.usedPercent,
            windowDurationMinutes: window.limitWindowSeconds / 60,
            resetsAt: Date(timeIntervalSince1970: window.resetAt),
            plan: CodexPlan(serverValue: usage.planType))
    }
}
