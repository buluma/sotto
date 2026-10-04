import Foundation

/// Inert origin retained for local sharing records and injected test transports.
public struct ShareServiceOrigin: Sendable, Equatable {
    public let baseURL: URL

    public static let disabled = ShareServiceOrigin(baseURL: URL(string: "https://sharing.invalid")!)

    private init(baseURL: URL) {
        self.baseURL = baseURL
    }

    #if DEBUG
    /// Test-only origin for injected fake transports; the default transport always refuses requests.
    public static func debugOverride(baseURL: URL) -> ShareServiceOrigin {
        ShareServiceOrigin(baseURL: baseURL)
    }
    #endif
}

/// A minimal, transport-agnostic HTTP request. Kept intentionally small so
/// `ShareRemoteClient` never depends on `URLRequest` directly and every
/// transport can be exercised with a lightweight fake in tests.
struct ShareHTTPRequest: Sendable {
    var method: String
    var path: String
    var headers: [String: String] = [:]
    var body: Data? = nil
}

struct ShareHTTPResponse: Sendable {
    var statusCode: Int
    var body: Data
}

enum ShareTransportError: Error, Sendable, Equatable {
    case unapprovedOrigin
    case network
}

/// An injectable seam for local contract tests. The default implementation cannot connect.
protocol ShareHTTPTransport: Sendable {
    func send(_ request: ShareHTTPRequest, origin: URL) async throws -> ShareHTTPResponse
}

/// No URLSession or network I/O exists in the personal fork's sharing transport.
final class DisabledShareHTTPTransport: ShareHTTPTransport, Sendable {
    func send(_ request: ShareHTTPRequest, origin: URL) async throws -> ShareHTTPResponse {
        throw ShareTransportError.unapprovedOrigin
    }
}

/// The owner-facing operations `ShareCoordinator` needs. The public
/// recipient fetch and abuse-report resources belong to the viewer, not this
/// native owner client, and are intentionally not modeled here.
protocol ShareRemoteClientProtocol: Sendable {
    func sendPersistedOperation(_ operation: ShareOutboxOperation, shareId: String, deviceToken: ShareDeviceToken)
        async throws -> ShareOperationResponse
    func capabilities() async throws -> ShareCapabilities

    func enrollOwner(
        ownerId: String,
        deviceSelector: String,
        deviceVerifier: String,
        recoveryVerifier: String?,
        idempotencyKey: String
    ) async throws -> ShareOwnerMetadata

    func fetchOwnerMetadata(deviceToken: ShareDeviceToken) async throws -> ShareOwnerMetadata

    func recoverOwner(
        recoveryToken: ShareRecoveryToken,
        deviceSelector: String,
        deviceVerifier: String,
        recoveryVerifier: String?,
        idempotencyKey: String
    ) async throws -> ShareOwnerMetadata

    func configureRecovery(
        deviceToken: ShareDeviceToken,
        recoveryVerifier: String?,
        isInitialSetup: Bool,
        currentRecoveryToken: ShareRecoveryToken?,
        idempotencyKey: String
    ) async throws -> ShareOwnerMetadata

    func listShares(deviceToken: ShareDeviceToken, cursor: String?, limit: Int) async throws -> ShareListPage

    func createShare(
        deviceToken: ShareDeviceToken,
        shareId: String,
        locator: String,
        contentRevision: Int,
        expiresAt: Date,
        envelope: ShareEnvelope,
        idempotencyKey: String
    ) async throws -> ShareResource

    func updateShareContent(
        deviceToken: ShareDeviceToken,
        shareId: String,
        locator: String,
        contentRevision: Int,
        envelope: ShareEnvelope,
        ifMatch: String,
        idempotencyKey: String
    ) async throws -> ShareResource

    func changeExpiry(
        deviceToken: ShareDeviceToken,
        shareId: String,
        expiresAt: Date,
        ifMatch: String,
        idempotencyKey: String
    ) async throws -> ShareResource

    func deleteShare(
        deviceToken: ShareDeviceToken,
        shareId: String,
        locatorCommitment: String,
        idempotencyKey: String
    ) async throws -> ShareDeletionReceipt
}

enum ShareOperationResponse: Sendable {
    case resource(ShareResource)
    case deletion(ShareDeletionReceipt)
}

// Fakes may implement the typed methods; the production override sends the
// stored bytes directly, without a decode/encode round trip.
extension ShareRemoteClientProtocol {
    func sendPersistedOperation(_ operation: ShareOutboxOperation, shareId: String, deviceToken: ShareDeviceToken)
        async throws -> ShareOperationResponse
    {
        let decoder = ShareServiceJSON.makeDecoder()
        switch operation.kind {
        case .create, .contentUpdate:
            let payload = try decoder.decode(ShareCreateOrUpdateRequestBody.self, from: operation.requestBody)
            if operation.kind == .create, let expiry = payload.expiresAt {
                return .resource(
                    try await createShare(
                        deviceToken: deviceToken, shareId: shareId, locator: payload.locator,
                        contentRevision: payload.contentRevision, expiresAt: expiry, envelope: payload.envelope,
                        idempotencyKey: operation.idempotencyKey))
            }
            guard let ifMatch = operation.ifMatch else { throw ShareCoordinatorError.corruptedOutboxOperation }
            return .resource(
                try await updateShareContent(
                    deviceToken: deviceToken, shareId: shareId, locator: payload.locator,
                    contentRevision: payload.contentRevision, envelope: payload.envelope, ifMatch: ifMatch,
                    idempotencyKey: operation.idempotencyKey))
        case .expiryChange:
            let payload = try decoder.decode(ShareExpiryChangeRequestBody.self, from: operation.requestBody)
            guard let ifMatch = operation.ifMatch else { throw ShareCoordinatorError.corruptedOutboxOperation }
            return .resource(
                try await changeExpiry(
                    deviceToken: deviceToken, shareId: shareId, expiresAt: payload.expiresAt,
                    ifMatch: ifMatch, idempotencyKey: operation.idempotencyKey))
        case .delete:
            let payload = try decoder.decode(ShareDeleteRequestBody.self, from: operation.requestBody)
            return .deletion(
                try await deleteShare(
                    deviceToken: deviceToken, shareId: shareId,
                    locatorCommitment: payload.locatorCommitment, idempotencyKey: operation.idempotencyKey))
        }
    }
}

/// Real implementation of the owner-facing subset of Share Service v1.
final class ShareRemoteClient: ShareRemoteClientProtocol {
    private let origin: ShareServiceOrigin
    private let transport: ShareHTTPTransport

    init(origin: ShareServiceOrigin, transport: ShareHTTPTransport) {
        self.origin = origin
        self.transport = transport
    }

    convenience init(origin: ShareServiceOrigin) {
        self.init(origin: origin, transport: DisabledShareHTTPTransport())
    }

    func sendPersistedOperation(_ operation: ShareOutboxOperation, shareId: String, deviceToken: ShareDeviceToken)
        async throws -> ShareOperationResponse
    {
        var headers = [
            "Authorization": deviceToken.authorizationHeaderValue, "Idempotency-Key": operation.idempotencyKey,
        ]
        var path = "/api/v1/shares/\(shareId)"
        let method: String
        switch operation.kind {
        case .create:
            method = "PUT"
            headers["If-None-Match"] = "*"
        case .contentUpdate, .expiryChange:
            guard let ifMatch = operation.ifMatch else { throw ShareCoordinatorError.corruptedOutboxOperation }
            headers["If-Match"] = ifMatch
            method = operation.kind == .contentUpdate ? "PUT" : "PATCH"
            if operation.kind == .expiryChange { path += "/expiry" }
        case .delete:
            return .deletion(
                try await perform(method: "DELETE", path: path, headers: headers, body: operation.requestBody))
        }
        return .resource(try await perform(method: method, path: path, headers: headers, body: operation.requestBody))
    }

    func capabilities() async throws -> ShareCapabilities {
        try await perform(method: "GET", path: "/api/v1/capabilities", headers: [:], body: nil)
    }

    func enrollOwner(
        ownerId: String,
        deviceSelector: String,
        deviceVerifier: String,
        recoveryVerifier: String?,
        idempotencyKey: String
    ) async throws -> ShareOwnerMetadata {
        let body = ShareOwnerEnrollmentRequestBody(
            ownerId: ownerId,
            deviceSelector: deviceSelector,
            deviceVerifier: deviceVerifier,
            recoveryVerifier: recoveryVerifier
        )
        return try await perform(
            method: "POST",
            path: "/api/v1/owners",
            headers: [
                "If-None-Match": "*",
                "Idempotency-Key": idempotencyKey,
            ],
            body: try ShareServiceJSON.makeEncoder().encode(body)
        )
    }

    func fetchOwnerMetadata(deviceToken: ShareDeviceToken) async throws -> ShareOwnerMetadata {
        try await perform(
            method: "GET",
            path: "/api/v1/owners/me",
            headers: ["Authorization": deviceToken.authorizationHeaderValue],
            body: nil
        )
    }

    func recoverOwner(
        recoveryToken: ShareRecoveryToken,
        deviceSelector: String,
        deviceVerifier: String,
        recoveryVerifier: String?,
        idempotencyKey: String
    ) async throws -> ShareOwnerMetadata {
        let body = ShareRecoveryRequestBody(
            deviceSelector: deviceSelector,
            deviceVerifier: deviceVerifier,
            recoveryVerifier: recoveryVerifier
        )
        return try await perform(
            method: "POST",
            path: "/api/v1/owners/recover",
            headers: [
                "Authorization": recoveryToken.authorizationHeaderValue,
                "Idempotency-Key": idempotencyKey,
            ],
            body: try ShareServiceJSON.makeEncoder().encode(body)
        )
    }

    func configureRecovery(
        deviceToken: ShareDeviceToken,
        recoveryVerifier: String?,
        isInitialSetup: Bool,
        currentRecoveryToken: ShareRecoveryToken?,
        idempotencyKey: String
    ) async throws -> ShareOwnerMetadata {
        var headers = [
            "Authorization": deviceToken.authorizationHeaderValue,
            "Idempotency-Key": idempotencyKey,
        ]
        if isInitialSetup {
            headers["If-None-Match"] = "*"
        }
        if let currentRecoveryToken {
            headers["Recovery-Authorization"] = currentRecoveryToken.authorizationHeaderValue
        }
        let body = ShareRecoveryConfigurationRequestBody(recoveryVerifier: recoveryVerifier)
        return try await perform(
            method: "PUT",
            path: "/api/v1/owners/recovery",
            headers: headers,
            body: try ShareServiceJSON.makeEncoder().encode(body)
        )
    }

    func listShares(deviceToken: ShareDeviceToken, cursor: String?, limit: Int) async throws -> ShareListPage {
        var components = URLComponents()
        components.path = "/api/v1/shares"
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { components.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
        let path = components.string!
        return try await perform(
            method: "GET",
            path: path,
            headers: ["Authorization": deviceToken.authorizationHeaderValue],
            body: nil
        )
    }

    func createShare(
        deviceToken: ShareDeviceToken,
        shareId: String,
        locator: String,
        contentRevision: Int,
        expiresAt: Date,
        envelope: ShareEnvelope,
        idempotencyKey: String
    ) async throws -> ShareResource {
        let body = ShareCreateOrUpdateRequestBody(
            locator: locator,
            contentRevision: contentRevision,
            expiresAt: expiresAt,
            envelope: envelope
        )
        return try await perform(
            method: "PUT",
            path: "/api/v1/shares/\(shareId)",
            headers: [
                "Authorization": deviceToken.authorizationHeaderValue,
                "If-None-Match": "*",
                "Idempotency-Key": idempotencyKey,
            ],
            body: try ShareServiceJSON.makeEncoder().encode(body)
        )
    }

    func updateShareContent(
        deviceToken: ShareDeviceToken,
        shareId: String,
        locator: String,
        contentRevision: Int,
        envelope: ShareEnvelope,
        ifMatch: String,
        idempotencyKey: String
    ) async throws -> ShareResource {
        let body = ShareCreateOrUpdateRequestBody(
            locator: locator,
            contentRevision: contentRevision,
            expiresAt: nil,
            envelope: envelope
        )
        return try await perform(
            method: "PUT",
            path: "/api/v1/shares/\(shareId)",
            headers: [
                "Authorization": deviceToken.authorizationHeaderValue,
                "If-Match": ifMatch,
                "Idempotency-Key": idempotencyKey,
            ],
            body: try ShareServiceJSON.makeEncoder().encode(body)
        )
    }

    func changeExpiry(
        deviceToken: ShareDeviceToken,
        shareId: String,
        expiresAt: Date,
        ifMatch: String,
        idempotencyKey: String
    ) async throws -> ShareResource {
        let body = ShareExpiryChangeRequestBody(expiresAt: expiresAt)
        return try await perform(
            method: "PATCH",
            path: "/api/v1/shares/\(shareId)/expiry",
            headers: [
                "Authorization": deviceToken.authorizationHeaderValue,
                "If-Match": ifMatch,
                "Idempotency-Key": idempotencyKey,
            ],
            body: try ShareServiceJSON.makeEncoder().encode(body)
        )
    }

    func deleteShare(
        deviceToken: ShareDeviceToken,
        shareId: String,
        locatorCommitment: String,
        idempotencyKey: String
    ) async throws -> ShareDeletionReceipt {
        let body = ShareDeleteRequestBody(locatorCommitment: locatorCommitment)
        return try await perform(
            method: "DELETE",
            path: "/api/v1/shares/\(shareId)",
            headers: [
                "Authorization": deviceToken.authorizationHeaderValue,
                "Idempotency-Key": idempotencyKey,
            ],
            body: try ShareServiceJSON.makeEncoder().encode(body)
        )
    }

    // MARK: - Request/response plumbing

    private func perform<Response: Decodable>(
        method: String,
        path: String,
        headers: [String: String],
        body: Data?
    ) async throws -> Response {
        let response = try await send(method: method, path: path, headers: headers, body: body)
        return try decode(Response.self, from: response)
    }

    private func send(
        method: String,
        path: String,
        headers: [String: String],
        body: Data?
    ) async throws -> ShareHTTPResponse {
        let request = ShareHTTPRequest(method: method, path: path, headers: headers, body: body)
        do {
            return try await transport.send(request, origin: origin.baseURL)
        } catch let error as ShareTransportError {
            switch error {
            case .unapprovedOrigin: throw ShareClientError.unapprovedOrigin
            case .network: throw ShareClientError.network
            }
        }
    }

    private func decode<Response: Decodable>(_ type: Response.Type, from response: ShareHTTPResponse) throws -> Response
    {
        guard (200..<300).contains(response.statusCode) else {
            throw ShareClientError.api(try decodeError(from: response))
        }
        do {
            return try ShareServiceJSON.makeDecoder().decode(Response.self, from: response.body)
        } catch {
            throw ShareClientError.unexpectedResponse
        }
    }

    private func decodeError(from response: ShareHTTPResponse) throws -> ShareAPIError {
        guard let envelope = try? ShareServiceJSON.makeDecoder().decode(ShareErrorEnvelope.self, from: response.body)
        else {
            throw ShareClientError.unexpectedResponse
        }
        let code = ShareServiceErrorCode(rawValue: envelope.error.code) ?? .unrecognized
        return ShareAPIError(code: code, retryable: envelope.error.retryable, requestId: envelope.error.requestId)
    }
}
