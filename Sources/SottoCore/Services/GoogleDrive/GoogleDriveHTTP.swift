import Foundation

public enum GoogleDriveError: LocalizedError, Sendable {
    case message(String)
    case http(Int)
    case api(status: Int, operation: String, reason: String?)

    public var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .http(401): return "Google Drive authorization expired. Disconnect and connect again."
        case .http(403):
            return "Google Drive denied access. Check folder permissions, storage space, and your Google Cloud setup."
        case .http(404): return "The Google Drive item is unavailable. Choose an accessible destination and retry."
        case .http(429): return "Google Drive is busy. Try the upload again later."
        case .http(let status): return "Google Drive returned an error (\(status)). Try again."
        case .api(let status, let operation, let reason):
            let detail = reason.map { " (\($0))" } ?? ""
            if reason == "storageQuotaExceeded" {
                return
                    "Google Drive storage is full (storageQuotaExceeded). Free space in this Google account, then retry."
            }
            return
                "Google Drive couldn’t \(operation) (HTTP \(status)\(detail)). Retry, or check the connected account and destination."
        }
    }
}

public struct GoogleDriveResponse: Sendable {
    public let data: Data
    public let status: Int
    public let headers: [String: String]

    public init(data: Data, status: Int, headers: [String: String] = [:]) {
        self.data = data
        self.status = status
        self.headers = Dictionary(
            headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
    }

    func requireSuccess() throws {
        guard (200..<300).contains(status) else { throw GoogleDriveError.http(status) }
    }

    func failure(operation: String) -> GoogleDriveError {
        .api(status: status, operation: operation, reason: providerErrorReason)
    }

    var providerErrorReason: String? {
        struct ErrorEnvelope: Decodable {
            struct Detail: Decodable { let reason: String? }
            struct GoogleError: Decodable { let errors: [Detail]? }
            let error: GoogleError?
        }
        guard let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
            let reason = envelope.error?.errors?.first?.reason,
            !reason.isEmpty, reason.count <= 40,
            reason.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
        else { return nil }
        return reason
    }
}

public protocol GoogleDriveTransport: Sendable {
    func send(_ request: URLRequest) async throws -> GoogleDriveResponse
}

/// Credentials are never forwarded through redirects, caches, or cookies.
public final class GoogleDriveHTTPTransport: GoogleDriveTransport, Sendable {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 60
        session = URLSession(configuration: configuration, delegate: GoogleDriveRedirectBlocker(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func send(_ request: URLRequest) async throws -> GoogleDriveResponse {
        guard let url = request.url, Self.isTrusted(url) else {
            throw GoogleDriveError.message("Google Drive returned an unexpected upload address.")
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GoogleDriveError.http(0) }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            if let name = entry.key as? String, let value = entry.value as? String { result[name] = value }
        }
        return GoogleDriveResponse(data: data, status: response.statusCode, headers: headers)
    }

    static func isTrusted(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && url.port == nil
            && ["www.googleapis.com", "oauth2.googleapis.com"].contains(url.host)
    }

}

private final class GoogleDriveRedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) { completionHandler(nil) }
}

func googleDriveForm(_ values: [String: String]) -> Data {
    var components = URLComponents()
    components.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    // URLComponents leaves '+' literal in a query; form parsers interpret it as a space.
    return Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
}
