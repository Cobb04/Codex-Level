import Foundation

public struct CodexProfile: Equatable, Sendable {
    public let username: String?
    public let displayName: String?
    public let lifetimeTokens: UInt64
    public let currentStreakDays: UInt64?

    public init(
        username: String? = nil,
        displayName: String? = nil,
        lifetimeTokens: UInt64,
        currentStreakDays: UInt64?
    ) {
        self.username = username
        self.displayName = displayName
        self.lifetimeTokens = lifetimeTokens
        self.currentStreakDays = currentStreakDays
    }

    public var preferredName: String? {
        [displayName, username]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

public struct CodexProfileClient: Sendable {
    private static let profileURL = URL(string: "https://chatgpt.com/backend-api/wham/profiles/me")!
    private let session: URLSession

    public init() {
        self.session = Self.makeSession()
    }

    public init(session: URLSession) {
        self.session = session
    }

    public func fetchProfile(credentials: CodexCredentials) async throws -> CodexProfile {
        var request = URLRequest(url: Self.profileURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")

        let data = try await data(for: request)

        struct ProfileResponse: Decodable {
            struct Identity: Decodable {
                let username: String?
                let displayName: String?

                enum CodingKeys: String, CodingKey {
                    case username
                    case displayName = "display_name"
                }
            }

            struct Stats: Decodable {
                let lifetimeTokens: UInt64
                let currentStreakDays: UInt64?

                enum CodingKeys: String, CodingKey {
                    case lifetimeTokens = "lifetime_tokens"
                    case currentStreakDays = "current_streak_days"
                }
            }

            let profile: Identity?
            let stats: Stats
        }

        guard let response = try? JSONDecoder().decode(ProfileResponse.self, from: data) else {
            throw CodexDataError.responseFormatChanged
        }
        return CodexProfile(
            username: response.profile?.username,
            displayName: response.profile?.displayName,
            lifetimeTokens: response.stats.lifetimeTokens,
            currentStreakDays: response.stats.currentStreakDays)
    }

    public func fetchLifetimeTokens(credentials: CodexCredentials) async throws -> UInt64 {
        try await fetchProfile(credentials: credentials).lifetimeTokens
    }

    private func data(for request: URLRequest) async throws -> Data {
        for attempt in 0 ..< 2 {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                if attempt == 0 { continue }
                throw CodexDataError.networkFailure
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw CodexDataError.networkFailure
            }
            switch httpResponse.statusCode {
            case 200:
                return data
            case 401, 403:
                throw CodexDataError.authenticationExpired
            case 408, 429, 500 ... 599:
                if attempt == 0 { continue }
                throw CodexDataError.networkFailure
            default:
                throw CodexDataError.networkFailure
            }
        }
        throw CodexDataError.networkFailure
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        return URLSession(
            configuration: configuration,
            delegate: CodexProfileRedirectDelegate(),
            delegateQueue: nil)
    }
}

final class CodexProfileRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func redirectRequest(_ request: URLRequest) -> URLRequest? {
        nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(redirectRequest(request))
    }
}
