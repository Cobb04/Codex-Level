import Foundation
import Testing
@testable import CodexLevelCore

@Suite(.serialized) struct CodexProfileClientTests {
    private let credentials = CodexCredentials(accessToken: "fake-access", accountID: "fake-account")

    @Test func readsIdentityLifetimeTokensAndCurrentStreakFromOneAuthenticatedGet() async throws {
        let session = makeSession { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/profiles/me")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-access")
            #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "fake-account")
            return response(
                request,
                status: 200,
                body: #"{"profile":{"username":"shannoncc","display_name":"Shannon Chen"},"stats":{"lifetime_tokens":123456,"current_streak_days":6}}"#)
        }

        let profile = try await CodexProfileClient(session: session).fetchProfile(credentials: credentials)

        #expect(profile.username == "shannoncc")
        #expect(profile.displayName == "Shannon Chen")
        #expect(profile.preferredName == "Shannon Chen")
        #expect(profile.lifetimeTokens == 123_456)
        #expect(profile.currentStreakDays == 6)
    }

    @Test func usernameIsUsedWhenDisplayNameIsMissing() async throws {
        let session = makeSession { request in
            response(
                request,
                status: 200,
                body: #"{"profile":{"username":"shannoncc"},"stats":{"lifetime_tokens":123456,"current_streak_days":6}}"#)
        }

        let profile = try await CodexProfileClient(session: session).fetchProfile(credentials: credentials)

        #expect(profile.username == "shannoncc")
        #expect(profile.displayName == nil)
        #expect(profile.preferredName == "shannoncc")
    }

    @Test func missingCurrentStreakDoesNotDiscardLifetimeTokens() async throws {
        let session = makeSession { request in
            response(request, status: 200, body: #"{"stats":{"lifetime_tokens":123456}}"#)
        }

        let profile = try await CodexProfileClient(session: session).fetchProfile(credentials: credentials)

        #expect(profile.lifetimeTokens == 123_456)
        #expect(profile.currentStreakDays == nil)
        #expect(profile.preferredName == nil)
    }

    @Test func missingLifetimeFieldIsAFormatChange() async {
        let session = makeSession { request in
            response(request, status: 200, body: #"{"stats":{}}"#)
        }

        await #expect(throws: CodexDataError.responseFormatChanged) {
            try await CodexProfileClient(session: session).fetchLifetimeTokens(credentials: credentials)
        }
    }

    @Test(arguments: [401, 403])
    func unauthorizedStatusMeansExpiredAuthentication(status: Int) async {
        let session = makeSession { request in
            response(request, status: status, body: "not retained")
        }

        await #expect(throws: CodexDataError.authenticationExpired) {
            try await CodexProfileClient(session: session).fetchLifetimeTokens(credentials: credentials)
        }
    }

    @Test func otherHTTPFailureIsANetworkFailure() async {
        let session = makeSession { request in
            response(request, status: 503, body: "not retained")
        }

        await #expect(throws: CodexDataError.networkFailure) {
            try await CodexProfileClient(session: session).fetchLifetimeTokens(credentials: credentials)
        }
    }

    @Test func retriesOneTransientHTTPFailure() async throws {
        let attempts = AttemptCounter()
        let session = makeSession { request in
            if attempts.increment() == 1 {
                return response(request, status: 503, body: "not retained")
            }
            return response(
                request,
                status: 200,
                body: #"{"profile":{"username":"shannoncc"},"stats":{"lifetime_tokens":123456,"current_streak_days":6}}"#)
        }

        let profile = try await CodexProfileClient(session: session).fetchProfile(credentials: credentials)

        #expect(profile.lifetimeTokens == 123_456)
        #expect(attempts.value == 2)
    }

    @Test func transportFailureIsANetworkFailure() async {
        let session = makeSession { _ in throw URLError(.notConnectedToInternet) }

        await #expect(throws: CodexDataError.networkFailure) {
            try await CodexProfileClient(session: session).fetchLifetimeTokens(credentials: credentials)
        }
    }

    @Test func retriesOneTransientTransportFailure() async throws {
        let attempts = AttemptCounter()
        let session = makeSession { request in
            if attempts.increment() == 1 {
                throw URLError(.timedOut)
            }
            return response(
                request,
                status: 200,
                body: #"{"profile":{"username":"shannoncc"},"stats":{"lifetime_tokens":123456,"current_streak_days":6}}"#)
        }

        let profile = try await CodexProfileClient(session: session).fetchProfile(credentials: credentials)

        #expect(profile.lifetimeTokens == 123_456)
        #expect(attempts.value == 2)
    }

    @Test func authenticatedProfileRequestRejectsRedirects() {
        let request = URLRequest(url: URL(string: "https://example.com/redirected")!)

        #expect(CodexProfileRedirectDelegate().redirectRequest(request) == nil)
    }

    private func makeSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        ProfileURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func response(
        _ request: URLRequest,
        status: Int,
        body: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil)!
        return (response, Data(body.utf8))
    }
}

private final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}

private final class ProfileURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
