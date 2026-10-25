import Foundation
import XCTest
@testable import SottoCore
@testable import SottoViewModels

final class GoogleDriveBackupTests: XCTestCase {
    private var testIdentity: GoogleDriveIdentity {
        GoogleDriveIdentity(permissionID: "owner", email: "owner@example.test")
    }
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

    func testExpiredRefreshTokenPromptsReconnectAndOtherHTTPFailuresPropagate() async throws {
        for status in [400, 401, 503] {
            let transport = DriveStubTransport()
            await transport.setTokenStatus(status)
            let store = DriveTestStore()
            let account = GoogleDriveAccount(store: store, transport: transport)
            try await account.importClient(
                Data(#"{"installed":{"client_id":"test.apps.googleusercontent.com"}}"#.utf8))
            let credential: [String: Any] = [
                "accessToken": "expired", "refreshToken": "refresh-token",
                "expiresAt": 0,
                "identity": ["permissionID": "owner", "email": "owner@example.test"],
            ]
            let data = try JSONSerialization.data(withJSONObject: credential)
            try store.setString(String(decoding: data, as: UTF8.self), forKey: "credential")

            do {
                _ = try await account.accessToken()
                XCTFail("Refresh status \(status) must fail")
            } catch let error as GoogleDriveError {
                if status == 400 || status == 401 {
                    XCTAssertTrue(error.localizedDescription.contains("Disconnect and connect again"))
                } else {
                    guard case .http(503) = error else { return XCTFail("Expected the original HTTP error") }
                }
            }
        }
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
        try await service.upload(snapshot, to: folder, identity: testIdentity) { _ in }
        let firstIDs = await transport.generated
        let firstCreates = await transport.createdFolders
        let reopened = GoogleDriveBackupService(account: account, transport: transport, ledgerURL: ledger)
        try await reopened.upload(snapshot, to: folder, identity: testIdentity) { _ in }
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
        do {
            try await service.upload(snapshot, to: destination, identity: testIdentity) { _ in };
            XCTFail("Expected lost response")
        } catch {}
        try await service.upload(snapshot, to: destination, identity: testIdentity) { _ in }
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
        try await service.upload(
            snapshot, to: GoogleDriveFolder(id: "destination", name: "Backups"), identity: testIdentity
        ) { _ in }
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

    func testReservationStoresMergeAcrossInstancesAndReuseExistingKeys() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("ledger.json")
        let first = GoogleDriveReservationStore(url: url)
        let second = GoogleDriveReservationStore(url: url)
        XCTAssertTrue(try first.read().isEmpty)
        XCTAssertTrue(try second.read().isEmpty)
        XCTAssertEqual(try first.reserve("meeting-a", generatedID: "id-a"), "id-a")
        XCTAssertEqual(try second.reserve("meeting-b", generatedID: "id-b"), "id-b")
        XCTAssertEqual(try first.reserve("meeting-b", generatedID: "unused-id"), "id-b")
        XCTAssertEqual(try second.read(), ["meeting-a": "id-a", "meeting-b": "id-b"])
        let lease = try first.acquireUploadLease()
        XCTAssertThrowsError(try second.acquireUploadLease())
        lease.release()
        let next = try second.acquireUploadLease()
        next.release()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<16 {
                group.addTask {
                    _ = try GoogleDriveReservationStore(url: url).reserve(
                        "concurrent-\(index)", generatedID: "id-\(index)")
                }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(try first.read().count, 18)
    }

    func testUploadRejectsAccountDifferentFromPreviewBeforeSendingRequests() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = DriveStubTransport()
        let service = GoogleDriveBackupService(
            account: try connectedAccount(transport: transport), transport: transport,
            ledgerURL: root.appendingPathComponent("ledger.json"))
        do {
            try await service.upload(
                try uploadSnapshot(root: root, size: 12),
                to: GoogleDriveFolder(id: "root", name: "My Drive"),
                identity: GoogleDriveIdentity(permissionID: "other-owner", email: "other@example.test")
            ) { _ in }
            XCTFail("An open preview must not follow an account switch")
        } catch { XCTAssertTrue(error.localizedDescription.contains("account changed")) }
        let count = await transport.requestCount
        XCTAssertEqual(count, 0)
    }

    func testMovedRootLevelMeetingFolderIsNotUpdatedInNewLocation() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = DriveStubTransport()
        let service = GoogleDriveBackupService(
            account: try connectedAccount(transport: transport), transport: transport,
            ledgerURL: root.appendingPathComponent("ledger.json"))
        let snapshot = try uploadSnapshot(root: root, size: 12)
        let destination = GoogleDriveFolder(id: "root", name: "My Drive")
        try await service.upload(snapshot, to: destination, identity: testIdentity) { _ in }
        await transport.moveBackupFolder(to: "shared-folder")
        do {
            try await service.upload(snapshot, to: destination, identity: testIdentity) { _ in }
            XCTFail("A moved backup must not receive new content")
        } catch { XCTAssertTrue(error.localizedDescription.contains("moved")) }
        let uploads = await transport.finishedUploads
        XCTAssertEqual(uploads.count, 1)
    }

    func testReconciliationDoesNotTrashManagedFileMovedElsewhere() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = DriveStubTransport()
        let service = GoogleDriveBackupService(
            account: try connectedAccount(transport: transport), transport: transport,
            ledgerURL: root.appendingPathComponent("ledger.json"))
        let snapshot = try uploadSnapshot(root: root, size: 12)
        let destination = GoogleDriveFolder(id: "destination", name: "Backups")
        try await service.upload(snapshot, to: destination, identity: testIdentity) { _ in }
        await transport.moveUploadedFile(to: "separate-archive")
        let withoutAudio = MeetingDriveBackupSnapshot(id: snapshot.id, title: snapshot.title, folder: root, files: [])
        do {
            try await service.upload(withoutAudio, to: destination, identity: testIdentity) { _ in }
            XCTFail("Do not reconcile files outside the backup")
        } catch { XCTAssertTrue(error.localizedDescription.contains("moved")) }
        let trashed = await transport.trashedIDs
        XCTAssertTrue(trashed.isEmpty)
    }

    @MainActor
    func testViewModelRetriesOnlyFailuresAndResetsCompletionForAnotherAccount() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = DriveStubTransport()
        let first = source(meeting(folder: root))
        let second = source(meeting(folder: root))
        let service = DriveViewModelService(failOnce: first.projection.automaticTranscription.id)
        let model = GoogleDriveBackupViewModel(account: try connectedAccount(transport: transport), service: service)
        model.prepare { [first, second] in [first, second] }
        try await waitForIdle(model)
        XCTAssertEqual(model.snapshots.count, 2)
        model.upload()
        try await waitForIdle(model)
        XCTAssertEqual(model.completed.count, 1)
        XCTAssertEqual(model.failures.count, 1)
        model.upload()
        try await waitForIdle(model)
        XCTAssertEqual(model.completed.count, 2)
        let calls = await service.calls
        XCTAssertEqual(calls.count, 3)
        model.disconnect()
        try await waitForIdle(model)
        XCTAssertTrue(model.completed.isEmpty)
        XCTAssertTrue(model.failures.isEmpty)
        let other = GoogleDriveIdentity(permissionID: "other-owner", email: "other@example.test")
        model.connect { other }
        try await waitForIdle(model)
        model.upload()
        try await waitForIdle(model)
        let identities = await service.identities
        XCTAssertEqual(identities.suffix(2), [other, other])
        await model.close()
    }

    func testReconciliationDoesNotTrashChildrenOfMovedPromptResultsDirectory() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = DriveStubTransport()
        let service = GoogleDriveBackupService(
            account: try connectedAccount(transport: transport), transport: transport,
            ledgerURL: root.appendingPathComponent("ledger.json"))
        let directory = root.appendingPathComponent("prompt-results")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let file = directory.appendingPathComponent("01-Summary.md")
        try Data("Summary".utf8).write(to: file)
        let snapshot = MeetingDriveBackupSnapshot(
            id: UUID(), title: "Meeting", folder: root,
            files: [.init(relativePath: "prompt-results/01-Summary.md", url: file, size: 7)])
        let destination = GoogleDriveFolder(id: "destination", name: "Backups")
        try await service.upload(snapshot, to: destination, identity: testIdentity) { _ in }
        await transport.moveNestedFolder(to: "separate-archive")
        let noResults = MeetingDriveBackupSnapshot(id: snapshot.id, title: snapshot.title, folder: root, files: [])
        do {
            try await service.upload(noResults, to: destination, identity: testIdentity) { _ in }
            XCTFail("Do not trash children of moved directories")
        } catch { XCTAssertTrue(error.localizedDescription.contains("moved")) }
        let trashed = await transport.trashedIDs
        XCTAssertTrue(trashed.isEmpty)
    }

    @MainActor
    func testNewDestinationClearsCompletionEvenWhenListingFails() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = source(meeting(folder: root))
        let service = DriveViewModelService()
        let model = GoogleDriveBackupViewModel(
            account: try connectedAccount(transport: DriveStubTransport()), service: service)
        model.prepare { [source] in [source] }
        try await waitForIdle(model)
        model.upload()
        try await waitForIdle(model)
        XCTAssertEqual(model.completed.count, 1)
        model.createFolder(name: "Another destination")
        try await waitForIdle(model)
        XCTAssertTrue(model.completed.isEmpty)
        XCTAssertEqual(model.destination.id, "new-destination")
        XCTAssertNotNil(model.errorMessage)
        await model.close()
    }

    @MainActor
    private func waitForIdle(_ model: GoogleDriveBackupViewModel) async throws {
        for _ in 0..<500 {
            if !model.isBusy { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Backup operation did not settle")
    }

    @MainActor
    func testCancellingUploadKeepsPreviewForRetryAndCloseOnlyRemovesStaging() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = source(meeting(folder: root))
        let model = GoogleDriveBackupViewModel(
            account: try connectedAccount(transport: DriveStubTransport()),
            service: DriveViewModelService(blockUploads: true))
        model.prepare { [source] in [source] }
        try await waitForIdle(model)
        let stagedFolder = try XCTUnwrap(model.snapshots.first?.folder)
        model.upload()
        for _ in 0..<100 where !model.isUploading { await Task.yield() }
        model.cancel()
        try await waitForIdle(model)
        XCTAssertFalse(model.isUploading)
        XCTAssertTrue(model.completed.isEmpty)
        XCTAssertEqual(model.snapshots.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedFolder.path))
        await model.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedFolder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
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
    var tokenStatus: Int?
    var trashedIDs: [String] = []
    var resources: [String: Resource] = [:]
    var sessions: [String: Session] = [:]
    var loseFolder = false
    var loseChunk = false
    func loseNextFolderResponse() { loseFolder = true }
    func loseNextChunkResponse() { loseChunk = true }
    func setTokenStatus(_ status: Int?) { tokenStatus = status }
    func moveBackupFolder(to parent: String) {
        if let item = resources.first(where: { $0.value.mimeType == "application/vnd.google-apps.folder" }) {
            resources[item.key] = Resource(parent: parent, mimeType: item.value.mimeType)
        }
    }
    func moveUploadedFile(to parent: String) {
        if let item = resources.first(where: { $0.value.mimeType == "audio/mp4" }) {
            resources[item.key] = Resource(parent: parent, mimeType: item.value.mimeType)
        }
    }
    func moveNestedFolder(to parent: String) {
        if let item = resources.first(where: {
            $0.value.mimeType == "application/vnd.google-apps.folder" && $0.value.parent.hasPrefix("id")
        }) {
            resources[item.key] = Resource(parent: parent, mimeType: item.value.mimeType)
        }
    }

    func send(_ request: URLRequest) async throws -> GoogleDriveResponse {
        requestCount += 1
        let url = try XCTUnwrap(request.url)
        if url.path == "/token" {
            if let tokenStatus { return .init(data: Data(), status: tokenStatus) }
            return try json([
                "access_token": "access-token", "refresh_token": "refresh-token", "expires_in": 3600,
                "scope": GoogleDriveAccount.scope,
            ])
        }
        if url.path == "/revoke" { return .init(data: Data(), status: 200) }
        if url.path.hasSuffix("/about") {
            return try json(["user": ["emailAddress": "owner@example.test", "permissionId": "owner"]])
        }
        if url.path.hasSuffix("/files/root") { return try json(["id": "real-root-id"]) }
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
        if request.httpMethod == "PATCH" {
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            if body?["trashed"] as? Bool == true { trashedIDs.append(id) }
            return try json(["id": id])
        }
        if let resource = resources[id] {
            return try json(["parents": [resource.parent], "mimeType": resource.mimeType, "trashed": false])
        }
        return .init(data: Data(), status: 404)
    }
    private func json(_ value: [String: Any]) throws -> GoogleDriveResponse {
        .init(data: try JSONSerialization.data(withJSONObject: value), status: 200)
    }
}

private actor DriveViewModelService: GoogleDriveBackingUp {
    var failOnce: UUID?
    let blockUploads: Bool
    var calls: [UUID] = []
    var identities: [GoogleDriveIdentity] = []
    init(failOnce: UUID? = nil, blockUploads: Bool = false) {
        self.failOnce = failOnce
        self.blockUploads = blockUploads
    }
    func folders(parent: String, identity: GoogleDriveIdentity) async throws -> [GoogleDriveFolder] {
        if parent == "new-destination" { throw GoogleDriveError.http(503) }
        return []
    }
    func createFolder(name: String, parent: String, identity: GoogleDriveIdentity) async throws -> GoogleDriveFolder {
        GoogleDriveFolder(id: "new-destination", name: name)
    }
    func upload(
        _ snapshot: MeetingDriveBackupSnapshot, to destination: GoogleDriveFolder, identity: GoogleDriveIdentity,
        progress: @escaping @Sendable (GoogleDriveBackupProgress) async -> Void
    ) async throws {
        calls.append(snapshot.id)
        identities.append(identity)
        if blockUploads {
            do { try await Task.sleep(for: .seconds(60)) } catch { throw URLError(.cancelled) }
        }
        if failOnce == snapshot.id {
            failOnce = nil
            throw GoogleDriveError.http(503)
        }
        try Task.checkCancellation()
    }
}
