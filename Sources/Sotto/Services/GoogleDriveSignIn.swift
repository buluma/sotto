import AppKit
import Foundation
import Network
import SottoCore

/// Google recommends an external browser and a loopback callback for desktop
/// clients. The listener binds only to IPv4 loopback and exists only for sign-in.
@MainActor
final class GoogleDriveSignIn {
    private var listener: NWListener?
    private var ready: CheckedContinuation<UInt16, Error>?
    private var callback: CheckedContinuation<URL, Error>?
    private var expectedState: String?
    private var port: UInt16?
    private var connections: [NWConnection] = []
    private var timeout: Task<Void, Never>?

    func connect(account: GoogleDriveAccount) async throws -> GoogleDriveIdentity {
        defer { stop() }
        return try await withTaskCancellationHandler {
            let port = try await start()
            try Task.checkCancellation()
            let authorization = try await account.authorization(redirectURI: "http://127.0.0.1:\(port)/oauth/callback")
            try Task.checkCancellation()
            expectedState = authorization.state
            let url = try await withCheckedThrowingContinuation { continuation in
                callback = continuation
                if !NSWorkspace.shared.open(authorization.url) {
                    fail(GoogleDriveError.message("The browser could not be opened for Google sign-in."))
                }
            }
            return try await account.complete(authorization, callback: url)
        } onCancel: {
            Task { @MainActor in self.fail(CancellationError()) }
        }
    }

    private func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                guard let self, self.connections.count < 8 else { connection.cancel(); return }
                self.connections.append(connection)
                connection.start(queue: .main)
                self.receive(connection, buffer: Data())
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = self.listener?.port?.rawValue else { return }
                    self.port = port
                    let continuation = self.ready
                    self.ready = nil
                    continuation?.resume(returning: port)
                case .failed:
                    self.fail(GoogleDriveError.message("The local Google sign-in callback could not be started."))
                default: break
                }
            }
        }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(180)) } catch { return }
            self?.fail(GoogleDriveError.message("Google sign-in timed out. Connect again."))
        }
        return try await withCheckedThrowingContinuation { continuation in
            ready = continuation
            listener.start(queue: .main)
        }
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                var buffer = buffer
                buffer.append(data ?? Data())
                guard buffer.count <= 8192 else { connection.cancel(); return }
                if buffer.range(of: Data("\r\n\r\n".utf8)) == nil, !complete, error == nil {
                    self.receive(connection, buffer: buffer)
                    return
                }
                guard let port = self.port,
                    let line = String(data: buffer, encoding: .utf8)?.components(separatedBy: "\r\n").first,
                    line.hasPrefix("GET /oauth/callback?"),
                    let target = line.split(separator: " ").dropFirst().first,
                    let url = URL(string: "http://127.0.0.1:\(port)\(target)"),
                    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                        .first(where: { $0.name == "state" })?.value == self.expectedState,
                    self.callback != nil
                else { connection.cancel(); return }
                let body = "Google sign-in received. You can close this window and return to Sotto."
                let response =
                    "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n\(body)"
                connection.send(
                    content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                let continuation = self.callback
                self.callback = nil
                continuation?.resume(returning: url)
            }
        }
    }

    private func fail(_ error: Error) {
        let ready = ready
        let callback = callback
        self.ready = nil
        self.callback = nil
        ready?.resume(throwing: error)
        callback?.resume(throwing: error)
        stop()
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        timeout?.cancel()
        timeout = nil
    }
}
