import CryptoKit
import Foundation
import Security

public struct GoogleCalendarIdentity: Codable, Sendable, Equatable {
    public let permissionID: String
    public let email: String
}

public struct GoogleCalendarAuthorization: Sendable {
    public let url: URL
    public let state: String
    let verifier: String
    let redirectURI: String
    let generation: UUID
}

/// One native-app OAuth identity. Client configuration and tokens stay in a
/// dedicated device-only Keychain namespace, never in the backup ledger.
public actor GoogleCalendarAccount {
    public static let shared = GoogleCalendarAccount(
        store: KeychainKeyValueStore(service: keychainService(bundleIdentifier: Bundle.main.bundleIdentifier)))
    public static let scopes = [
        "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
        "https://www.googleapis.com/auth/calendar.events.readonly",
    ]
    private let store: any KeyValueStore
    private let transport: any GoogleDriveTransport
    private var generation = UUID()

    static func keychainService(bundleIdentifier: String?) -> String {
        bundleIdentifier == "com.sotto.dev" ? "com.sotto.dev.google-calendar" : "com.sotto.google-calendar"
    }

    public nonisolated static var isConnected: Bool {
        let store = KeychainKeyValueStore(service: keychainService(bundleIdentifier: Bundle.main.bundleIdentifier))
        return (try? store.getString("credential")) != nil
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
        let identity: GoogleCalendarIdentity
    }
    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double
        let scope: String?
    }

    public init(
        store: any KeyValueStore = KeychainKeyValueStore(service: "com.sotto.google-calendar"),
        transport: any GoogleDriveTransport = GoogleDriveHTTPTransport()
    ) {
        self.store = store
        self.transport = transport
    }

    public func hasClient() throws -> Bool { try store.getString("client") != nil }
    public func identity() throws -> GoogleCalendarIdentity? { try credential()?.identity }

    /// Copy only the desktop client configuration. Calendar keeps its own
    /// authorization and credentials, and an existing Calendar client wins.
    @discardableResult
    public func reuseDriveClient(from drive: GoogleDriveAccount = .shared) async throws -> Bool {
        guard try !hasClient(), try credential() == nil else { return false }
        guard let data = try await drive.clientConfigurationForReuse() else { return false }
        // The actor can be re-entered while reading the Drive account.
        guard try !hasClient(), try credential() == nil else { return false }
        try importClient(data)
        return true
    }

    func sessionMarker() -> UUID { generation }

    func ensureSession(_ marker: UUID) throws {
        guard generation == marker, try credential() != nil else { throw CancellationError() }
    }

    public func importClient(_ data: Data) throws {
        let client: Client
        do { client = try JSONDecoder().decode(InstalledClient.self, from: data).installed } catch {
            throw GoogleCalendarError.message("Choose the OAuth JSON downloaded for a Google Cloud Desktop app client.")
        }
        guard client.client_id.hasSuffix(".apps.googleusercontent.com"),
            !client.client_id.contains(where: \.isWhitespace)
        else {
            throw GoogleCalendarError.message("The file does not contain a valid Google Desktop app client ID.")
        }
        guard try credential() == nil else {
            throw GoogleCalendarError.message("Disconnect Google Calendar before changing its OAuth client.")
        }
        try save(client, key: "client")
        generation = UUID()
    }

    public func authorization(redirectURI: String) throws -> GoogleCalendarAuthorization {
        let client = try loadClient()
        generation = UUID()
        let verifier = try Self.randomURLSafe()
        let state = try Self.randomURLSafe()
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            "client_id": client.client_id, "redirect_uri": redirectURI, "response_type": "code",
            "scope": Self.scopes.joined(separator: " "), "state": state, "code_challenge": challenge,
            "code_challenge_method": "S256",
            "access_type": "offline", "prompt": "consent select_account",
        ].sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return GoogleCalendarAuthorization(
            url: components.url!, state: state, verifier: verifier,
            redirectURI: redirectURI, generation: generation)
    }

    public func complete(_ authorization: GoogleCalendarAuthorization, callback: URL) async throws
        -> GoogleCalendarIdentity
    {
        guard generation == authorization.generation else { throw CancellationError() }
        let values = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard values.filter({ $0.name == "state" }).count == 1,
            values.first(where: { $0.name == "state" })?.value == authorization.state,
            callback.scheme == "http", callback.host == "127.0.0.1",
            callback.path == URL(string: authorization.redirectURI)?.path,
            callback.port == URL(string: authorization.redirectURI)?.port
        else { throw GoogleCalendarError.message("Google sign-in could not be verified. Connect again.") }
        guard !values.contains(where: { $0.name == "error" }),
            let code = values.first(where: { $0.name == "code" })?.value, !code.isEmpty
        else { throw GoogleCalendarError.message("Google Calendar access was not granted.") }
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
            token.scope.map({ granted in
                let scopes = Set(granted.split(separator: " ").map(String.init))
                return Self.scopes.allSatisfy(scopes.contains)
            }) != false
        else {
            throw GoogleCalendarError.message(
                "Google Calendar did not grant the requested calendar access. Connect again.")
        }
        var request = URLRequest(
            url: URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList/primary")!)
        request.setValue("Bearer \(token.access_token)", forHTTPHeaderField: "Authorization")
        let response = try await transport.send(request)
        try response.requireCalendarSuccess()
        struct PrimaryCalendar: Decodable { let id: String }
        let primary = try JSONDecoder().decode(PrimaryCalendar.self, from: response.data)
        let identity = GoogleCalendarIdentity(permissionID: primary.id, email: primary.id)
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
            throw GoogleCalendarError.message("Connect your Google account first.")
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
        } catch GoogleCalendarError.http(400), GoogleCalendarError.http(401) {
            throw GoogleCalendarError.message("Google Calendar sign-in expired. Disconnect and connect again.")
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
        // Revoking a Google grant can revoke other scopes for the same OAuth
        // client, including Drive. Forget this connection locally instead.
        try store.delete("credential")
        generation = UUID()
    }

    private func requestToken(_ values: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.httpBody = googleDriveForm(values)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let response = try await transport.send(request)
        try response.requireCalendarSuccess()
        return try JSONDecoder().decode(TokenResponse.self, from: response.data)
    }

    private func loadClient() throws -> Client {
        guard let value = try store.getString("client"), let data = value.data(using: .utf8) else {
            throw GoogleCalendarError.message("Import your Google Cloud Desktop app OAuth JSON before connecting.")
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
            throw GoogleCalendarError.message("Secure sign-in could not be started.")
        }
        return base64URL(Data(bytes))
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
