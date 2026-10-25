import Foundation

public struct GoogleDriveFolder: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct GoogleDriveBackupProgress: Sendable {
    public let meetingID: UUID
    public let path: String
    public let uploadedBytes: Int64
    public let totalBytes: Int64
}

public protocol GoogleDriveBackingUp: Sendable {
    func folders(parent: String, identity: GoogleDriveIdentity) async throws -> [GoogleDriveFolder]
    func createFolder(name: String, parent: String, identity: GoogleDriveIdentity) async throws -> GoogleDriveFolder
    func upload(
        _ snapshot: MeetingDriveBackupSnapshot, to destination: GoogleDriveFolder, identity: GoogleDriveIdentity,
        progress: @escaping @Sendable (GoogleDriveBackupProgress) async -> Void) async throws
}

/// Only manual uploads call this service. Reserved Drive IDs are saved before
/// creates, so an uncertain response is retried against the same remote ID.
public actor GoogleDriveBackupService: GoogleDriveBackingUp {
    public static let shared = GoogleDriveBackupService()
    private let account: GoogleDriveAccount
    private let transport: any GoogleDriveTransport
    private let ledgerURL: URL
    private struct UploadSession {
        let url: URL
        let source: URL
    }
    private var sessions: [String: UploadSession] = [:]
    private var busy = false
    private static let folderMIME = "application/vnd.google-apps.folder"

    public init(
        account: GoogleDriveAccount = .shared,
        transport: any GoogleDriveTransport = GoogleDriveHTTPTransport(), ledgerURL: URL? = nil
    ) {
        self.account = account
        self.transport = transport
        self.ledgerURL =
            ledgerURL
            ?? URL(fileURLWithPath: AppPaths.appSupportDir)
            .appendingPathComponent("google-drive-backup-ids.json")
    }

    public func folders(parent: String, identity: GoogleDriveIdentity) async throws -> [GoogleDriveFolder] {
        let parent = try await resolveParent(parent, identity: identity)
        try Self.validateID(parent)
        var folders: [GoogleDriveFolder] = []
        var page: String?
        repeat {
            let response = try await request(
                "GET", path: "files",
                query: [
                    "q": "'\(parent)' in parents and trashed = false and mimeType = '\(Self.folderMIME)'",
                    "fields": "nextPageToken,files(id,name)", "pageSize": "1000", "pageToken": page ?? "",
                ], identity: identity)
            struct Page: Decodable { let files: [GoogleDriveFolder]; let nextPageToken: String? }
            let result = try JSONDecoder().decode(Page.self, from: response.data)
            folders += result.files
            page = result.nextPageToken
        } while page != nil
        return folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func createFolder(name: String, parent: String, identity: GoogleDriveIdentity) async throws
        -> GoogleDriveFolder
    {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 200 else {
            throw GoogleDriveError.message("Enter a folder name of up to 200 characters.")
        }
        let parent = try await resolveParent(parent, identity: identity)
        try Self.validateID(parent)
        // A user-created destination gets its own reservation too: retrying a
        // lost response with the same name and parent cannot duplicate it.
        let key = "\(identity.permissionID)|destination|\(parent)|\(name)"
        let id = try await reserve(key, identity: identity)
        try await ensureFolder(id: id, name: name, parent: parent, identity: identity)
        return GoogleDriveFolder(id: id, name: name)
    }

    public func upload(
        _ snapshot: MeetingDriveBackupSnapshot, to destination: GoogleDriveFolder, identity: GoogleDriveIdentity,
        progress: @escaping @Sendable (GoogleDriveBackupProgress) async -> Void
    ) async throws {
        guard !busy else {
            throw GoogleDriveError.message("Another Google Drive backup is running. Try again when it finishes.")
        }
        busy = true
        defer { busy = false }
        let lease = try GoogleDriveReservationStore(url: ledgerURL).acquireUploadLease()
        defer { lease.release() }
        let parent = try await resolveParent(destination.id, identity: identity)
        try Self.validateID(destination.id)
        let prefix = "\(identity.permissionID)|\(destination.id)|\(snapshot.id.uuidString)|"
        let folderID = try await reserve(prefix + "folder", identity: identity)
        try await ensureFolder(
            id: folderID, name: "\(snapshot.title.prefix(120)) — \(snapshot.id.uuidString)",
            parent: parent, identity: identity)
        var folders = ["": folderID]
        var uploaded: Int64 = 0
        // Publish the manifest last; a failed operation is visibly partial.
        let files = snapshot.files.sorted {
            if ($0.relativePath == "manifest.json") != ($1.relativePath == "manifest.json") {
                return $1.relativePath == "manifest.json"
            }
            return $0.relativePath < $1.relativePath
        }
        for file in files {
            try Task.checkCancellation()
            let parts = file.relativePath.split(separator: "/").map(String.init)
            guard !parts.isEmpty, parts.allSatisfy({ $0 != "." && $0 != ".." }), parts.count <= 2,
                file.url.standardizedFileURL.path.hasPrefix(snapshot.folder.standardizedFileURL.path + "/")
            else { throw GoogleDriveError.message("The backup contains an invalid artifact path.") }
            let directory = parts.dropLast().joined(separator: "/")
            if folders[directory] == nil {
                let id = try await reserve(prefix + "directory:" + directory, identity: identity)
                try await ensureFolder(id: id, name: directory, parent: folderID, identity: identity)
                folders[directory] = id
            }
            guard let parent = folders[directory], let name = parts.last else { continue }
            let id = try await reserve(prefix + "file:" + file.relativePath, identity: identity)
            let baseline = uploaded
            try await uploadFile(file, id: id, name: name, parent: parent, identity: identity) { count in
                await progress(
                    GoogleDriveBackupProgress(
                        meetingID: snapshot.id, path: file.relativePath,
                        uploadedBytes: baseline + count, totalBytes: snapshot.totalBytes))
            }
            uploaded += file.size
        }
        // Remove only files recorded as ours and absent from this snapshot.
        // Trash is recoverable in Drive and never affects local artifacts.
        let currentPaths = Set(snapshot.files.map { prefix + "file:" + $0.relativePath })
        let stale = try ledger().filter { $0.key.hasPrefix(prefix + "file:") && !currentPaths.contains($0.key) }
        for (key, id) in stale {
            try Task.checkCancellation()
            try Self.validateID(id)
            let relativePath = String(key.dropFirst((prefix + "file:").count))
            let directory = relativePath.split(separator: "/").dropLast().joined(separator: "/")
            guard let expectedParent = directory.isEmpty ? folderID : try ledger()[prefix + "directory:" + directory]
            else {
                throw GoogleDriveError.message("A backup directory is missing from the local upload ledger.")
            }
            if !directory.isEmpty {
                guard
                    let parent = try await metadata(
                        id: expectedParent, parent: folderID, identity: identity, restoreTrashed: false),
                    parent.mimeType == Self.folderMIME
                else {
                    throw GoogleDriveError.message("A backup directory is no longer available in the meeting folder.")
                }
            }
            guard try await metadata(id: id, parent: expectedParent, identity: identity, restoreTrashed: false) != nil
            else { continue }
            let response = try await request(
                "PATCH", path: "files/\(id)", body: ["trashed": true],
                identity: identity, accepting: [404])
            if response.status != 404 { try response.requireSuccess() }
        }
    }

    private func uploadFile(
        _ file: MeetingDriveBackupFile, id: String, name: String, parent: String,
        identity: GoogleDriveIdentity, progress: @escaping @Sendable (Int64) async -> Void
    ) async throws {
        let existing = try await metadata(id: id, parent: parent, identity: identity)
        guard existing?.mimeType != Self.folderMIME else {
            throw GoogleDriveError.message("A backup file was replaced by a folder in Drive.")
        }
        let exists = existing != nil
        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        guard try handle.seekToEnd() == UInt64(file.size) else {
            throw GoogleDriveError.message("A staged backup file changed. Close the preview and prepare it again.")
        }
        // Never resume old bytes into a newly prepared snapshot, even when
        // its path in Drive and length happen to match the previous version.
        var session = sessions[id].flatMap { $0.source == file.url ? $0.url : nil }
        var offset: Int64 = 0
        if let existingSession = session {
            let response = try await sendChunk(
                Data(), to: existingSession, range: "bytes */\(file.size)", identity: identity)
            if response.status == 308 {
                offset = try Self.nextOffset(response, size: file.size)
            } else if (200..<300).contains(response.status) {
                sessions[id] = nil; await progress(file.size); return
            } else if response.status == 404 || response.status == 410 {
                session = nil; sessions[id] = nil
            } else {
                try response.requireSuccess()
            }
        }
        if session == nil {
            var body: [String: Any] = ["name": name, "trashed": false]
            if !exists { body["id"] = id; body["parents"] = [parent] }
            var response = try await request(
                exists ? "PATCH" : "POST", path: exists ? "files/\(id)" : "files",
                query: ["uploadType": "resumable", "fields": "id"], body: body,
                headers: [
                    "X-Upload-Content-Type": Self.mimeType(file.relativePath),
                    "X-Upload-Content-Length": "\(file.size)",
                ],
                identity: identity, upload: true, accepting: [409])
            if response.status == 409, !exists {
                // A previous uncertain create may have committed even when
                // its metadata was not visible at the first lookup.
                guard let item = try await metadata(id: id, parent: parent, identity: identity),
                    item.mimeType != Self.folderMIME
                else {
                    throw GoogleDriveError.http(409)
                }
                response = try await request(
                    "PATCH", path: "files/\(id)",
                    query: ["uploadType": "resumable", "fields": "id"], body: ["name": name, "trashed": false],
                    headers: [
                        "X-Upload-Content-Type": Self.mimeType(file.relativePath),
                        "X-Upload-Content-Length": "\(file.size)",
                    ],
                    identity: identity, upload: true)
            }
            guard let location = response.headers["location"], let url = URL(string: location),
                GoogleDriveHTTPTransport.isTrusted(url), url.host == "www.googleapis.com",
                url.path.hasPrefix("/upload/drive/v3/files")
            else { throw GoogleDriveError.message("Google Drive did not return a valid resumable upload address.") }
            session = url
            sessions[id] = UploadSession(url: url, source: file.url)
        }
        guard let session else { throw GoogleDriveError.http(0) }
        var stalled = 0
        repeat {
            try Task.checkCancellation()
            try handle.seek(toOffset: UInt64(offset))
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            guard !data.isEmpty || file.size == 0 else {
                throw GoogleDriveError.message("A staged backup file is incomplete.")
            }
            let range = file.size == 0 ? "bytes */0" : "bytes \(offset)-\(offset + Int64(data.count) - 1)/\(file.size)"
            let response: GoogleDriveResponse
            do {
                let sent = try await sendChunk(data, to: session, range: range, identity: identity)
                if sent.status == 429 || sent.status >= 500 { throw GoogleDriveError.http(sent.status) }
                response = sent
            } catch {
                try Task.checkCancellation()
                guard stalled < 3 else { throw error }
                stalled += 1
                try await Task.sleep(for: .seconds(stalled))
                // Never guess whether bytes committed after a lost response.
                response = try await sendChunk(Data(), to: session, range: "bytes */\(file.size)", identity: identity)
            }
            if (200..<300).contains(response.status) {
                sessions[id] = nil
                await progress(file.size)
                return
            }
            guard response.status == 308 else { throw GoogleDriveError.http(response.status) }
            let next = try Self.nextOffset(response, size: file.size)
            if next <= offset { stalled += 1 } else { stalled = 0 }
            guard stalled <= 3 else { throw GoogleDriveError.message("The upload stopped making progress. Retry it.") }
            offset = next
            await progress(offset)
        } while offset <= file.size
    }

    static func nextOffset(_ response: GoogleDriveResponse, size: Int64) throws -> Int64 {
        guard let range = response.headers["range"] else { return 0 }
        guard range.hasPrefix("bytes=0-"), let end = Int64(range.dropFirst(8)), end >= 0, end < size else {
            throw GoogleDriveError.message("Google Drive returned an invalid upload position.")
        }
        return end + 1
    }

    private func sendChunk(_ data: Data, to url: URL, range: String, identity: GoogleDriveIdentity) async throws
        -> GoogleDriveResponse
    {
        let token = try await token(for: identity)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(range, forHTTPHeaderField: "Content-Range")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = data
        return try await transport.send(request)
    }

    private func ensureFolder(id: String, name: String, parent: String, identity: GoogleDriveIdentity) async throws {
        if let existing = try await metadata(id: id, parent: parent, identity: identity) {
            guard existing.mimeType == Self.folderMIME else {
                throw GoogleDriveError.message("A backup folder was replaced by a file in Drive.")
            }
            return
        }
        let response = try await request(
            "POST", path: "files",
            body: [
                "id": id, "name": name,
                "mimeType": Self.folderMIME, "parents": [parent],
            ], identity: identity, accepting: [409])
        if response.status == 409 {
            guard let item = try await metadata(id: id, parent: parent, identity: identity),
                item.mimeType == Self.folderMIME
            else {
                throw GoogleDriveError.http(409)
            }
        }
    }

    private struct Metadata: Decodable { let mimeType: String; let parents: [String]?; let trashed: Bool }
    private func metadata(id: String, parent: String, identity: GoogleDriveIdentity, restoreTrashed: Bool = true)
        async throws -> Metadata?
    {
        let response = try await request(
            "GET", path: "files/\(id)", query: ["fields": "mimeType,parents,trashed"],
            identity: identity, accepting: [404])
        if response.status == 404 { return nil }
        let value = try JSONDecoder().decode(Metadata.self, from: response.data)
        guard value.parents?.contains(parent) == true else {
            throw GoogleDriveError.message(
                "A backup item was moved in Drive. Move it back before updating this backup.")
        }
        if value.trashed && restoreTrashed {
            _ = try await request("PATCH", path: "files/\(id)", body: ["trashed": false], identity: identity)
        }
        return value
    }

    private func reserve(_ key: String, identity: GoogleDriveIdentity) async throws -> String {
        if let id = try ledger()[key] { return id }
        let response = try await request(
            "GET", path: "files/generateIds", query: ["count": "1", "space": "drive"], identity: identity)
        struct IDs: Decodable { let ids: [String] }
        guard let id = try JSONDecoder().decode(IDs.self, from: response.data).ids.first else {
            throw GoogleDriveError.http(0)
        }
        try Self.validateID(id)
        return try GoogleDriveReservationStore(url: ledgerURL).reserve(key, generatedID: id)
    }

    private func ledger() throws -> [String: String] {
        try GoogleDriveReservationStore(url: ledgerURL).read()
    }

    private func resolveParent(_ parent: String, identity: GoogleDriveIdentity) async throws -> String {
        try Self.validateID(parent)
        guard parent == "root" else { return parent }
        let response = try await request("GET", path: "files/root", query: ["fields": "id"], identity: identity)
        struct Root: Decodable { let id: String }
        let id = try JSONDecoder().decode(Root.self, from: response.data).id
        try Self.validateID(id)
        return id
    }
    private func token(for expected: GoogleDriveIdentity) async throws -> String {
        try Task.checkCancellation()
        let token = try await account.accessToken()
        guard try await account.identity() == expected else {
            throw GoogleDriveError.message(
                "The Google account changed. Close this backup and reopen it to review the connected account.")
        }
        return token
    }
    private func request(
        _ method: String, path: String, query: [String: String] = [:], body: [String: Any]? = nil,
        headers: [String: String] = [:], identity: GoogleDriveIdentity, upload: Bool = false, accepting: Set<Int> = []
    ) async throws -> GoogleDriveResponse {
        let token = try await token(for: identity)
        var components = URLComponents(string: "https://www.googleapis.com/\(upload ? "upload/" : "")drive/v3/\(path)")!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let response = try await transport.send(request)
        if !accepting.contains(response.status), !(200..<300).contains(response.status) {
            throw GoogleDriveError.api(
                status: response.status, operation: Self.operationDescription(method: method, path: path),
                reason: response.providerErrorReason)
        }
        return response
    }
    private static func operationDescription(method: String, path: String) -> String {
        return switch (method, path) {
        case ("GET", "files/root"): "find My Drive"
        case ("GET", "files/generateIds"): "reserve an upload ID"
        case ("GET", "files"): "list destination folders"
        case ("POST", "files"): "create the folder or upload session"
        case ("PATCH", let value) where value.hasPrefix("files/"): "update an existing Drive item"
        case ("GET", let value) where value.hasPrefix("files/"): "check a Drive item"
        default: "complete a Drive request"
        }
    }
    private static func validateID(_ id: String) throws {
        guard !id.isEmpty, id.count <= 256,
            id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else {
            throw GoogleDriveError.message("Google Drive returned an invalid item identifier.")
        }
    }
    private static func mimeType(_ path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension {
        case "m4a": return "audio/mp4"
        case "json": return "application/json"
        case "md": return "text/markdown"
        default: return "application/octet-stream"
        }
    }
}
