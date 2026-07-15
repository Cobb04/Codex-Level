import Foundation
import Testing
@testable import CodexLevelCore

@Suite(.serialized) struct CodexOAuthUsageClientTests {
    private let credentials = CodexCredentials(accessToken: "fake-access", accountID: "fake-account")

    @Test func readsWeeklyWindowFromAuthenticatedUsageRequest() async throws {
        let session = makeSession { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-access")
            #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "fake-account")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            return response(
                request,
                status: 200,
                body: #"{"rate_limit":{"primary_window":{"used_percent":12,"reset_at":1784000000,"limit_window_seconds":18000},"secondary_window":{"used_percent":34,"reset_at":1784217600,"limit_window_seconds":604800}}}"#)
        }

        let limit = try await CodexOAuthUsageClient(session: session)
            .readWeeklyRateLimit(credentials: credentials)

        #expect(limit.usedPercent == 34)
        #expect(limit.windowDurationMinutes == 10_080)
        #expect(limit.resetsAt == Date(timeIntervalSince1970: 1_784_217_600))
    }

    private func makeSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        CodexOAuthUsageURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexOAuthUsageURLProtocol.self]
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

private final class CodexOAuthUsageURLProtocol: URLProtocol, @unchecked Sendable {
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
