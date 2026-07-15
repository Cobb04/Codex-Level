import Foundation

public struct CodexResetCredit: Equatable, Identifiable, Sendable {
    public let id: String
    public let expiresAt: Date?

    public init(id: String, expiresAt: Date?) {
        self.id = id
        self.expiresAt = expiresAt
    }
}

/// Banked rate-limit resets adapted from CodexBar's MIT-licensed Codex provider.
public struct CodexResetCreditsClient: Sendable {
    private static let creditsURL = URL(
        string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
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
            delegate: CodexSameOriginRedirectDelegate(),
            delegateQueue: nil)
    }

    public init(session: URLSession) {
        self.session = session
    }

    public func fetchAvailableCredits(
        credentials: CodexCredentials,
        now: Date = Date()
    ) async throws -> [CodexResetCredit] {
        var request = URLRequest(
            url: Self.creditsURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        request.setValue("CodexBar", forHTTPHeaderField: "User-Agent")

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

        struct CreditsResponse: Decodable {
            struct Credit: Decodable {
                let id: String
                let status: String
                let expiresAt: Date?

                enum CodingKeys: String, CodingKey {
                    case id
                    case status
                    case expiresAt = "expires_at"
                }
            }

            let credits: [Credit]
            let availableCount: Int

            enum CodingKeys: String, CodingKey {
                case credits
                case availableCount = "available_count"
            }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeISO8601Date)
        guard let payload = try? decoder.decode(CreditsResponse.self, from: data),
              payload.availableCount >= 0
        else {
            throw CodexDataError.responseFormatChanged
        }

        return payload.credits
            .filter { $0.status == "available" && ($0.expiresAt.map { $0 > now } ?? true) }
            .sorted { lhs, rhs in
                switch (lhs.expiresAt, rhs.expiresAt) {
                case let (lhsDate?, rhsDate?):
                    return lhsDate == rhsDate ? lhs.id < rhs.id : lhsDate < rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.id < rhs.id
                }
            }
            .map { CodexResetCredit(id: $0.id, expiresAt: $0.expiresAt) }
    }

    private static func decodeISO8601Date(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let seconds = ISO8601DateFormatter()
        seconds.formatOptions = [.withInternetDateTime]
        if let date = fractional.date(from: raw) ?? seconds.date(from: raw) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
    }
}

final class CodexSameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(Self.redirectRequest(
            originalURL: task.originalRequest?.url,
            redirectRequest: request))
    }

    static func redirectRequest(originalURL: URL?, redirectRequest request: URLRequest) -> URLRequest? {
        guard let originalURL, let redirectedURL = request.url,
              originalURL.scheme?.lowercased() == "https",
              redirectedURL.scheme?.lowercased() == "https",
              originalURL.host?.lowercased() == redirectedURL.host?.lowercased(),
              normalizedPort(originalURL) == normalizedPort(redirectedURL)
        else {
            return nil
        }
        return request
    }

    private static func normalizedPort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : nil)
    }
}
