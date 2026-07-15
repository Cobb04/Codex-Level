import Foundation

public struct CodexCredentials: Equatable, Sendable {
    public let accessToken: String
    public let accountID: String

    public init(accessToken: String, accountID: String) {
        self.accessToken = accessToken
        self.accountID = accountID
    }

    public static func authFileURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let codexHome = environment["CODEX_HOME"].flatMap { value in
            value.isEmpty ? nil : URL(fileURLWithPath: value, isDirectory: true)
        } ?? homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        return codexHome.appendingPathComponent("auth.json", isDirectory: false)
    }

    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> Self {
        try load(from: authFileURL(environment: environment, homeDirectory: homeDirectory))
    }

    public static func load(from url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CodexDataError.notLoggedIn
        }
        guard let data = try? Data(contentsOf: url) else {
            throw CodexDataError.notLoggedIn
        }
        return try parse(data)
    }

    public static func parse(_ data: Data) throws -> Self {
        struct AuthFile: Decodable {
            struct Tokens: Decodable {
                let accessToken: String
                let accountID: String

                enum CodingKeys: String, CodingKey {
                    case accessToken = "access_token"
                    case accountID = "account_id"
                }
            }

            let tokens: Tokens
        }

        guard let authFile = try? JSONDecoder().decode(AuthFile.self, from: data),
              !authFile.tokens.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !authFile.tokens.accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CodexDataError.responseFormatChanged
        }
        return Self(
            accessToken: authFile.tokens.accessToken,
            accountID: authFile.tokens.accountID)
    }
}
