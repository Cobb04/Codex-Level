import Foundation
import Testing
@testable import CodexLevelCore

@Suite struct CodexCredentialsTests {
    @Test func parsesRequiredOAuthFields() throws {
        let data = Data(#"{"tokens":{"access_token":"fake-access","account_id":"fake-account","refresh_token":"unused"}}"#.utf8)

        let credentials = try CodexCredentials.parse(data)

        #expect(credentials.accessToken == "fake-access")
        #expect(credentials.accountID == "fake-account")
    }

    @Test func rejectsMissingRequiredOAuthFields() {
        let data = Data(#"{"tokens":{"access_token":"fake-access"}}"#.utf8)

        #expect(throws: CodexDataError.responseFormatChanged) {
            try CodexCredentials.parse(data)
        }
    }

    @Test func rejectsWhitespaceOnlyOAuthFields() {
        let data = Data(#"{"tokens":{"access_token":"   ","account_id":"\n"}}"#.utf8)

        #expect(throws: CodexDataError.responseFormatChanged) {
            try CodexCredentials.parse(data)
        }
    }

    @Test func usesCodexHomeWhenSet() {
        let url = CodexCredentials.authFileURL(
            environment: ["CODEX_HOME": "/tmp/fake-codex-home"],
            homeDirectory: URL(fileURLWithPath: "/tmp/fake-user"))

        #expect(url.path == "/tmp/fake-codex-home/auth.json")
    }

    @Test func usesDotCodexUnderHomeByDefault() {
        let url = CodexCredentials.authFileURL(
            environment: [:],
            homeDirectory: URL(fileURLWithPath: "/tmp/fake-user"))

        #expect(url.path == "/tmp/fake-user/.codex/auth.json")
    }

    @Test func missingAuthFileMeansNotLoggedIn() {
        let missingURL = URL(fileURLWithPath: "/tmp/codex-level-missing-\(UUID().uuidString)/auth.json")

        #expect(throws: CodexDataError.notLoggedIn) {
            try CodexCredentials.load(from: missingURL)
        }
    }
}
