import CryptoKit
import Foundation
import Security

public struct GoogleDriveIdentity: Codable, Sendable, Equatable {
    public let permissionID: String
    public let email: String
}

public struct GoogleDriveAuthorization: Sendable {
    public let url: URL
    public let state: String
    let verifier: String
    let redirectURI: String
    let generation: UUID
}

/// One native-app OAuth identity. Client configuration and tokens stay in a
/// dedicated device-only Keychain namespace, never in the backup ledger.
public actor GoogleDriveAccount {
    public static let shared = GoogleDriveAccount(
        store: KeychainKeyValueStore(service: keychainService(bundleIdentifier: Bundle.main.bundleIdentifier)))
    public static let scope = "https://www.googleapis.com/auth/drive.file"
    private let store: any KeyValueStore
    private let transport: any GoogleDriveTransport
    private var generation = UUID()

    static func keychainService(bundleIdentifier: String?) -> String {
        bundleIdentifier == "com.sotto.dev" ? "com.sotto.dev.google-drive" : "com.sotto.google-drive"
    }

    private struct Client: Codable {
        let client_id: String
        let client_secret: String?
    }
    private struct InstalledClient: Decodable { let installed: Client }
    private struct Credential: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        let identity: GoogleDriveIdentity
    }
    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double
        let scope: String?
    }

    public init(
        store: any KeyValueStore = KeychainKeyValueStore(service: "com.sotto.google-drive"),
        transport: any GoogleDriveTransport = GoogleDriveHTTPTransport()
    ) {
        self.store = store
        self.transport = transport
    }

    public func hasClient() throws -> Bool { try store.getString("client") != nil }
    public func identity() throws -> GoogleDriveIdentity? { try credential()?.identity }

    public func importClient(_ data: Data) throws {
        let client: Client
        do { client = try JSONDecoder().decode(InstalledClient.self, from: data).installed } catch {
            throw GoogleDriveError.message("Choose the OAuth JSON downloaded for a Google Cloud Desktop app client.")
        }
        guard client.client_id.hasSuffix(".apps.googleusercontent.com"),
            !client.client_id.contains(where: \.isWhitespace)
        else {
            throw GoogleDriveError.message("The file does not contain a valid Google Desktop app client ID.")
        }
        guard try credential() == nil else {
            throw GoogleDriveError.message("Disconnect Google Drive before changing its OAuth client.")
        }
        try save(client, key: "client")
        generation = UUID()
    }

    public func authorization(redirectURI: String) throws -> GoogleDriveAuthorization {
        let client = try loadClient()
        generation = UUID()
        let verifier = try Self.randomURLSafe()
        let state = try Self.randomURLSafe()
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            "client_id": client.client_id, "redirect_uri": redirectURI, "response_type": "code",
            "scope": Self.scope, "state": state, "code_challenge": challenge, "code_challenge_method": "S256",
            "access_type": "offline", "prompt": "consent select_account",
        ].sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return GoogleDriveAuthorization(
            url: components.url!, state: state, verifier: verifier,
            redirectURI: redirectURI, generation: generation)
    }

    public func complete(_ authorization: GoogleDriveAuthorization, callback: URL) async throws -> GoogleDriveIdentity {
        guard generation == authorization.generation else { throw CancellationError() }
        let values = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard values.filter({ $0.name == "state" }).count == 1,
            values.first(where: { $0.name == "state" })?.value == authorization.state,
            callback.scheme == "http", callback.host == "127.0.0.1",
            callback.path == URL(string: authorization.redirectURI)?.path,
            callback.port == URL(string: authorization.redirectURI)?.port
        else { throw GoogleDriveError.message("Google sign-in could not be verified. Connect again.") }
        guard !values.contains(where: { $0.name == "error" }),
            let code = values.first(where: { $0.name == "code" })?.value, !code.isEmpty
        else { throw GoogleDriveError.message("Google Drive access was not granted.") }
        let expectedGeneration = generation
        let client = try loadClient()
        let token = try await requestToken([
            "code": code, "client_id": client.client_id, "client_secret": client.client_secret ?? "",
            "redirect_uri": authorization.redirectURI, "code_verifier": authorization.verifier,
            "grant_type": "authorization_code",
        ])
        try Task.checkCancellation()
        guard expectedGeneration == generation else { throw CancellationError() }
        guard let refresh = token.refresh_token, !refresh.isEmpty,
            token.scope?.split(separator: " ").contains(Substring(Self.scope)) != false
        else { throw GoogleDriveError.message("Google Drive did not grant the requested file access. Connect again.") }
        var request = URLRequest(
            url: URL(string: "https://www.googleapis.com/drive/v3/about?fields=user(emailAddress,permissionId)")!)
        request.setValue("Bearer \(token.access_token)", forHTTPHeaderField: "Authorization")
        let response = try await transport.send(request)
        try response.requireSuccess()
        struct About: Decodable {
            struct User: Decodable { let emailAddress: String; let permissionId: String }
            let user: User
        }
        let user = try JSONDecoder().decode(About.self, from: response.data).user
        let identity = GoogleDriveIdentity(permissionID: user.permissionId, email: user.emailAddress)
        try Task.checkCancellation()
        guard expectedGeneration == generation else { throw CancellationError() }
        try save(
            Credential(
                accessToken: token.access_token, refreshToken: refresh,
                expiresAt: Date().addingTimeInterval(token.expires_in), identity: identity), key: "credential")
        generation = UUID()
        return identity
    }

    public func accessToken() async throws -> String {
        guard var credential = try credential() else {
            throw GoogleDriveError.message("Connect your Google account first.")
        }
        if credential.expiresAt.timeIntervalSinceNow > 90 { return credential.accessToken }
        let expectedGeneration = generation
        let client = try loadClient()
        let token: TokenResponse
        do {
            token = try await requestToken([
                "client_id": client.client_id, "client_secret": client.client_secret ?? "",
                "refresh_token": credential.refreshToken, "grant_type": "refresh_token",
            ])
        } catch GoogleDriveError.http(400), GoogleDriveError.http(401) {
            throw GoogleDriveError.message("Google Drive sign-in expired. Disconnect and connect again.")
        }
        try Task.checkCancellation()
        guard expectedGeneration == generation else { throw CancellationError() }
        credential.accessToken = token.access_token
        credential.refreshToken = token.refresh_token ?? credential.refreshToken
        credential.expiresAt = Date().addingTimeInterval(token.expires_in)
        try save(credential, key: "credential")
        return credential.accessToken
    }

    public func disconnect() async throws {
        let token = try credential()?.refreshToken
        // Forget locally before the network request, even when offline.
        try store.delete("credential")
        generation = UUID()
        guard let token else { return }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = googleDriveForm(["token": token])
        do {
            let response = try await transport.send(request)
            guard (200..<300).contains(response.status) || response.status == 400 else {
                throw GoogleDriveError.http(response.status)
            }
        } catch {
            throw GoogleDriveError.message(
                "Disconnected locally. Google could not confirm revocation; remove Sotto access in your Google account settings."
            )
        }
    }

    private func requestToken(_ values: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.httpBody = googleDriveForm(values)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let response = try await transport.send(request)
        try response.requireSuccess()
        return try JSONDecoder().decode(TokenResponse.self, from: response.data)
    }

    private func loadClient() throws -> Client {
        guard let value = try store.getString("client"), let data = value.data(using: .utf8) else {
            throw GoogleDriveError.message("Import your Google Cloud Desktop app OAuth JSON before connecting.")
        }
        return try JSONDecoder().decode(Client.self, from: data)
    }
    private func credential() throws -> Credential? {
        guard let value = try store.getString("credential") else { return nil }
        return try JSONDecoder().decode(Credential.self, from: Data(value.utf8))
    }
    private func save<T: Encodable>(_ value: T, key: String) throws {
        try store.setString(String(decoding: JSONEncoder().encode(value), as: UTF8.self), forKey: key)
    }
    private static func randomURLSafe() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw GoogleDriveError.message("Secure sign-in could not be started.")
        }
        return base64URL(Data(bytes))
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
