import Foundation
import Testing
@testable import CodexLevelCore

@Suite(.serialized) struct CodexResetCreditsClientTests {
    private let credentials = CodexCredentials(accessToken: "fake-access", accountID: "fake-account")
    private let now = Date(timeIntervalSince1970: 1_784_092_800)

    @Test func readsOnlyAvailableUnexpiredResetCredits() async throws {
        let session = makeSession { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")
            #expect(request.timeoutInterval == 30)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-access")
            #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-ID") == "fake-account")
            #expect(request.value(forHTTPHeaderField: "OpenAI-Beta") == "codex-1")
            #expect(request.value(forHTTPHeaderField: "originator") == "Codex Desktop")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "CodexBar")
            return response(
                request,
                status: 200,
                body: #"{"credits":[{"id":"later","status":"available","expires_at":"2026-07-18T00:00:00Z"},{"id":"expired","status":"available","expires_at":"2026-07-14T00:00:00Z"},{"id":"used","status":"redeemed","expires_at":"2026-07-17T00:00:00Z"},{"id":"sooner","status":"available","expires_at":"2026-07-16T00:00:00.000Z"},{"id":"no-expiry","status":"available","expires_at":null}],"available_count":3}"#)
        }

        let credits = try await CodexResetCreditsClient(session: session)
            .fetchAvailableCredits(credentials: credentials, now: now)

        #expect(credits.map(\.id) == ["sooner", "later", "no-expiry"])
        #expect(credits.last?.expiresAt == nil)
    }

    @Test func rejectsNegativeAvailableCount() async throws {
        let session = makeSession { request in
            response(request, status: 200, body: #"{"credits":[],"available_count":-1}"#)
        }

        await #expect(throws: CodexDataError.responseFormatChanged) {
            _ = try await CodexResetCreditsClient(session: session)
                .fetchAvailableCredits(credentials: credentials, now: now)
        }
    }

    @Test func authenticatedRedirectGuardAllowsOnlySameOriginHTTPS() {
        let original = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
        let sameOrigin = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/")!)
        let otherOrigin = URLRequest(url: URL(string: "https://example.com/rate-limit-reset-credits")!)

        #expect(CodexSameOriginRedirectDelegate.redirectRequest(
            originalURL: original,
            redirectRequest: sameOrigin) != nil)
        #expect(CodexSameOriginRedirectDelegate.redirectRequest(
            originalURL: original,
            redirectRequest: otherOrigin) == nil)
    }

    private func makeSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        CodexResetCreditsURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexResetCreditsURLProtocol.self]
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

private final class CodexResetCreditsURLProtocol: URLProtocol, @unchecked Sendable {
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
