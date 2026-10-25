import Foundation
import XCTest
@testable import SottoCore
@testable import SottoViewModels

final class GoogleDriveBackupTests: XCTestCase {
    func testPreviewUsesCurrentTranscriptAndOnlyManagedArtifactsWithoutChangingSource() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("retained audio".utf8).write(to: root.appendingPathComponent("microphone-raw.m4a"))
        try Data("private lock".utf8).write(to: root.appendingPathComponent("session.lock"))
        try Data("unrelated".utf8).write(to: root.appendingPathComponent("personal.txt"))
        let original = Data("old derived view".utf8)
        try original.write(to: root.appendingPathComponent("meeting.md"))
        let row = meeting(folder: root)
        let preparer = MeetingDriveBackupPreparer()
        let snapshots = try await preparer.prepare([source(row)])
        let snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertTrue(snapshot.files.contains { $0.relativePath == "microphone-raw.m4a" })
        XCTAssertFalse(
            snapshot.files.contains { $0.relativePath == "session.lock" || $0.relativePath == "personal.txt" })
        XCTAssertTrue(
            try String(contentsOf: snapshot.folder.appendingPathComponent("meeting.md")).contains("Current transcript"))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("meeting.md")), original)
        try Data("changed after review".utf8).write(to: root.appendingPathComponent("microphone-raw.m4a"))
        XCTAssertEqual(
            try Data(contentsOf: snapshot.folder.appendingPathComponent("microphone-raw.m4a")),
            Data("retained audio".utf8))
        await preparer.cleanup(snapshots)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshot.folder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }

    func testPreviewSupportsAudioRemovedMeetingsAndRejectsProcessingAndSymlinks() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let preparer = MeetingDriveBackupPreparer()
        var row = meeting(folder: root)
        row.filePath = nil
        let snapshots = try await preparer.prepare([source(row)])
        XCTAssertFalse(snapshots.flatMap(\.files).contains { $0.relativePath.hasSuffix("m4a") })
        await preparer.cleanup(snapshots)
        row.status = .processing
        do { _ = try await preparer.prepare([source(row)]); XCTFail("Processing meetings must not upload") } catch {
            XCTAssertTrue(error.localizedDescription.contains("finished processing"))
        }
        row.status = .completed
        let secret = root.appendingPathComponent("secret")
        try Data("not a recording".utf8).write(to: secret)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("microphone-raw.m4a"), withDestinationURL: secret)
        do { _ = try await preparer.prepare([source(row)]); XCTFail("Symlinks must not upload") } catch {
            XCTAssertTrue(error.localizedDescription.contains("regular local file"))
        }
    }

    func testOAuthUsesPKCEOnlyDriveFileAndRejectsForgedCallbackWithoutNetwork() async throws {
        let transport = DriveStubTransport()
        let store = DriveTestStore()
        let account = GoogleDriveAccount(store: store, transport: transport)
        try await account.importClient(
            Data(
                #"{"installed":{"client_id":"test.apps.googleusercontent.com","client_secret":"desktop-client"}}"#.utf8)
        )
        let auth = try await account.authorization(redirectURI: "http://127.0.0.1:12345/oauth/callback")
        let query = URLComponents(url: auth.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "scope" }?.value, GoogleDriveAccount.scope)
        XCTAssertEqual(query.first { $0.name == "code_challenge_method" }?.value, "S256")
        XCTAssertEqual(query.first { $0.name == "access_type" }?.value, "offline")
        XCTAssertNil(query.first { $0.name == "client_secret" })
        do {
            _ = try await account.complete(
                auth, callback: URL(string: "http://127.0.0.1:12345/oauth/callback?state=forged&code=code")!)
            XCTFail("Forged callback must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("verified")) }
        let count = await transport.requestCount
        XCTAssertEqual(count, 0)
        let identity = try await account.identity()
        XCTAssertNil(identity)
        XCTAssertEqual(String(decoding: googleDriveForm(["value": "a+b&c"]), as: UTF8.self), "value=a%2Bb%26c")
        XCTAssertFalse(
            GoogleDriveHTTPTransport.isTrusted(URL(string: "https://www.googleapis.com.attacker.test/upload")!))
        XCTAssertFalse(GoogleDriveHTTPTransport.isTrusted(URL(string: "https://attacker@www.googleapis.com/upload")!))
    }

    func testOAuthCompletionAndDisconnectStoreCredentialsOnlyUntilRevocation() async throws {
        let transport = DriveStubTransport()
        let store = DriveTestStore()
        let account = GoogleDriveAccount(store: store, transport: transport)
        try await account.importClient(Data(#"{"installed":{"client_id":"test.apps.googleusercontent.com"}}"#.utf8))
        let auth = try await account.authorization(redirectURI: "http://127.0.0.1:12345/oauth/callback")
        let identity = try await account.complete(
            auth, callback: URL(string: "http://127.0.0.1:12345/oauth/callback?state=\(auth.state)&code=test")!)
        XCTAssertEqual(identity.email, "owner@example.test")
        XCTAssertNotNil(try store.getString("credential"))
        try await account.disconnect()
        XCTAssertNil(try store.getString("credential"))
        let disconnected = try await account.identity()
        XCTAssertNil(disconnected)
        XCTAssertNotNil(try store.getString("client"))
    }

    func testUploadReusesPersistedIDsAndUpdatesExistingFilesAfterReopeningService() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = DriveStubTransport()
        let account = try connectedAccount(transport: transport)
        let ledger = root.appendingPathComponent("ledger.json")
        let snapshot = try uploadSnapshot(root: root, size: 2_100_000)
        let folder = GoogleDriveFolder(id: "destination", name: "Backups")
        let service = GoogleDriveBackupService(account: account, transport: transport, ledgerURL: ledger)
        try await service.upload(snapshot, to: folder) { _ in }
        let firstIDs = await transport.generated
        let firstCreates = await transport.createdFolders
        let reopened = GoogleDriveBackupService(account: account, transport: transport, ledgerURL: ledger)
        try await reopened.upload(snapshot, to: folder) { _ in }
        let secondIDs = await transport.generated
        let secondCreates = await transport.createdFolders
        XCTAssertEqual(secondIDs, firstIDs)
        XCTAssertEqual(secondCreates, firstCreates)
        let uploads = await transport.finishedUploads
        XCTAssertEqual(uploads.count, 2)
        XCTAssertEqual(uploads.first, try Data(contentsOf: snapshot.files[0].url))
        XCTAssertEqual(uploads.last, uploads.first)
        XCTAssertFalse(try String(contentsOf: ledger).contains("access-token"))
    }

    func testLostFolderCreateResponseRetriesReservedIDWithoutDuplicate() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = DriveStubTransport()
        await transport.loseNextFolderResponse()
        let service = GoogleDriveBackupService(
            account: try connectedAccount(transport: transport), transport: transport,
            ledgerURL: root.appendingPathComponent("ledger.json"))
        let snapshot = try uploadSnapshot(root: root, size: 12)
        let destination = GoogleDriveFolder(id: "destination", name: "Backups")
        do { try await service.upload(snapshot, to: destination) { _ in }; XCTFail("Expected lost response") } catch {}
        try await service.upload(snapshot, to: destination) { _ in }
        let creates = await transport.createdFolders
        XCTAssertEqual(creates, 1)
    }

    func testLostChunkResponseProbesOffsetAndContinuesWithoutDuplicatingBytes() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = DriveStubTransport()
        await transport.loseNextChunkResponse()
        let service = GoogleDriveBackupService(
            account: try connectedAccount(transport: transport), transport: transport,
            ledgerURL: root.appendingPathComponent("ledger.json"))
        let snapshot = try uploadSnapshot(root: root, size: 2_100_000)
        try await service.upload(snapshot, to: GoogleDriveFolder(id: "destination", name: "Backups")) { _ in }
        let probes = await transport.probes
        let uploads = await transport.finishedUploads
        XCTAssertEqual(probes, 1)
        XCTAssertEqual(uploads.last, try Data(contentsOf: snapshot.files[0].url))
    }

    func testInvalidResumableRangeFailsInsteadOfGuessing() throws {
        XCTAssertEqual(
            try GoogleDriveBackupService.nextOffset(
                .init(data: Data(), status: 308, headers: ["Range": "bytes=0-1048575"]), size: 2_000_000), 1_048_576)
        XCTAssertThrowsError(
            try GoogleDriveBackupService.nextOffset(
                .init(data: Data(), status: 308, headers: ["Range": "bytes=0-999"]), size: 2))
        XCTAssertThrowsError(
            try GoogleDriveBackupService.nextOffset(
                .init(data: Data(), status: 308, headers: ["Range": "bytes=50-60"]), size: 100))
    }

    private func temporaryFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(
            "DriveTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func meeting(folder: URL) -> Transcription {
        Transcription(
            fileName: "Meeting", meetingArtifactFolderPath: folder.path,
            cleanTranscript: "Current transcript", status: .completed, sourceType: .meeting, userNotes: "Notes")
    }
    private func source(_ row: Transcription) -> MeetingDriveBackupSource {
        MeetingDriveBackupSource(
            projection: .init(
                automaticTranscription: row,
                attribution: SpeakerAttributionResolver.resolve(transcription: row), correctionsApplied: false),
            promptResults: [])
    }
    private func connectedAccount(transport: DriveStubTransport) throws -> GoogleDriveAccount {
        let store = DriveTestStore()
        let value: [String: Any] = [
            "accessToken": "access-token", "refreshToken": "refresh-token",
            "expiresAt": Date().addingTimeInterval(3600).timeIntervalSinceReferenceDate,
            "identity": ["permissionID": "owner", "email": "owner@example.test"],
        ]
        try store.setString(
            String(decoding: JSONSerialization.data(withJSONObject: value), as: UTF8.self), forKey: "credential")
        return GoogleDriveAccount(store: store, transport: transport)
    }
    private func uploadSnapshot(root: URL, size: Int) throws -> MeetingDriveBackupSnapshot {
        let url = root.appendingPathComponent("meeting-playback.m4a")
        let data = Data((0..<size).map { UInt8($0 % 251) })
        try data.write(to: url)
        return MeetingDriveBackupSnapshot(
            id: UUID(), title: "Test", folder: root,
            files: [MeetingDriveBackupFile(relativePath: url.lastPathComponent, url: url, size: Int64(data.count))])
    }
}

private final class DriveTestStore: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    func getString(_ key: String) throws -> String? { lock.withLock { values[key] } }
    func setString(_ value: String, forKey key: String) throws { lock.withLock { values[key] = value } }
    func delete(_ key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
}

private actor DriveStubTransport: GoogleDriveTransport {
    struct Resource { let parent: String; let mimeType: String }
    struct Session { let id: String; let parent: String; var bytes = Data() }
    var generated = 0
    var createdFolders = 0
    var finishedUploads: [Data] = []
    var probes = 0
    var requestCount = 0
    var resources: [String: Resource] = [:]
    var sessions: [String: Session] = [:]
    var loseFolder = false
    var loseChunk = false
    func loseNextFolderResponse() { loseFolder = true }
    func loseNextChunkResponse() { loseChunk = true }

    func send(_ request: URLRequest) async throws -> GoogleDriveResponse {
        requestCount += 1
        let url = try XCTUnwrap(request.url)
        if url.path == "/token" {
            return try json([
                "access_token": "access-token", "refresh_token": "refresh-token", "expires_in": 3600,
                "scope": GoogleDriveAccount.scope,
            ])
        }
        if url.path == "/revoke" { return .init(data: Data(), status: 200) }
        if url.path.hasSuffix("/about") {
            return try json(["user": ["emailAddress": "owner@example.test", "permissionId": "owner"]])
        }
        if url.path.hasSuffix("generateIds") {
            generated += 1
            return try json(["ids": ["id\(generated)"]])
        }
        if url.path.hasPrefix("/upload/") {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let sessionID = query.first(where: { $0.name == "upload_id" })?.value {
                var session = try XCTUnwrap(sessions[sessionID])
                let range = request.value(forHTTPHeaderField: "Content-Range") ?? ""
                let total = Int64(range.split(separator: "/").last ?? "0") ?? 0
                if range.hasPrefix("bytes */") {
                    probes += 1
                } else {
                    let start = Int64(range.dropFirst(6).split(separator: "-").first ?? "-1")
                    XCTAssertEqual(start, Int64(session.bytes.count))
                    session.bytes.append(request.httpBody ?? Data())
                    sessions[sessionID] = session
                    if loseChunk { loseChunk = false; throw URLError(.networkConnectionLost) }
                }
                if Int64(session.bytes.count) == total {
                    resources[session.id] = Resource(parent: session.parent, mimeType: "audio/mp4")
                    finishedUploads.append(session.bytes)
                    return try json(["id": session.id])
                }
                return .init(
                    data: Data(), status: 308,
                    headers: session.bytes.isEmpty ? [:] : ["range": "bytes=0-\(session.bytes.count - 1)"])
            }
            let body = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
            let id = body["id"] as? String ?? url.lastPathComponent
            let parent = (body["parents"] as? [String])?.first ?? resources[id]?.parent ?? "destination"
            let sessionID = "s\(sessions.count)"
            sessions[sessionID] = Session(id: id, parent: parent)
            return .init(
                data: Data(), status: 200,
                headers: ["Location": "https://www.googleapis.com/upload/drive/v3/files?upload_id=\(sessionID)"])
        }
        if request.httpMethod == "POST" {
            let body = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
            let id = try XCTUnwrap(body["id"] as? String)
            resources[id] = Resource(
                parent: (body["parents"] as? [String])?.first ?? "root",
                mimeType: body["mimeType"] as? String ?? "")
            createdFolders += 1
            if loseFolder { loseFolder = false; throw URLError(.networkConnectionLost) }
            return try json(["id": id])
        }
        let id = url.lastPathComponent
        if request.httpMethod == "PATCH" { return try json(["id": id]) }
        if let resource = resources[id] {
            return try json(["parents": [resource.parent], "mimeType": resource.mimeType, "trashed": false])
        }
        return .init(data: Data(), status: 404)
    }
    private func json(_ value: [String: Any]) throws -> GoogleDriveResponse {
        .init(data: try JSONSerialization.data(withJSONObject: value), status: 200)
    }
}
