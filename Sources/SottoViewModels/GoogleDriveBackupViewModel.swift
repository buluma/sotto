import Foundation
import Observation
import SottoCore

@MainActor
@Observable
public final class GoogleDriveBackupViewModel {
    public private(set) var identity: GoogleDriveIdentity?
    public private(set) var hasClient = false
    public private(set) var snapshots: [MeetingDriveBackupSnapshot] = []
    public private(set) var folders: [GoogleDriveFolder] = []
    public private(set) var path = [GoogleDriveFolder(id: "root", name: "My Drive")]
    public var destination: GoogleDriveFolder { path.last ?? GoogleDriveFolder(id: "root", name: "My Drive") }
    public private(set) var isBusy = false
    public private(set) var isUploading = false
    public private(set) var progress: GoogleDriveBackupProgress?
    public private(set) var completed: Set<UUID> = []
    public private(set) var failures: [UUID: String] = [:]
    public var errorMessage: String?
    public private(set) var statusMessage: String?
    private let account: GoogleDriveAccount
    private let service: any GoogleDriveBackingUp
    private let preparer: MeetingDriveBackupPreparer
    private var operation: Task<Void, Never>?

    public init(
        account: GoogleDriveAccount = .shared, service: any GoogleDriveBackingUp = GoogleDriveBackupService.shared,
        preparer: MeetingDriveBackupPreparer = MeetingDriveBackupPreparer()
    ) {
        self.account = account
        self.service = service
        self.preparer = preparer
    }

    public func prepare(sources: @escaping @Sendable () async throws -> [MeetingDriveBackupSource]) {
        run {
            self.hasClient = try await self.account.hasClient()
            self.identity = try await self.account.identity()
            self.snapshots = try await self.preparer.prepare(sources())
            if self.identity != nil { self.folders = try await self.service.folders(parent: self.destination.id) }
        }
    }

    public func importClient(_ data: Data) {
        run {
            try await self.account.importClient(data)
            self.hasClient = true
        }
    }

    public func connect(using signIn: @escaping @MainActor () async throws -> GoogleDriveIdentity) {
        run {
            self.identity = try await signIn()
            self.folders = try await self.service.folders(parent: self.destination.id)
        }
    }

    public func disconnect() {
        run {
            defer {
                self.identity = nil
                self.folders = []
                self.path = [GoogleDriveFolder(id: "root", name: "My Drive")]
            }
            try await self.account.disconnect()
        }
    }

    public func openFolder(_ folder: GoogleDriveFolder) {
        run {
            let folders = try await self.service.folders(parent: folder.id)
            self.path.append(folder)
            self.folders = folders
            self.completed.removeAll()
        }
    }

    public func goBack() {
        guard path.count > 1 else { return }
        let parent = path[path.count - 2]
        run {
            self.folders = try await self.service.folders(parent: parent.id)
            self.path.removeLast()
            self.completed.removeAll()
        }
    }

    public func createFolder(name: String) {
        run {
            let folder = try await self.service.createFolder(name: name, parent: self.destination.id)
            self.path.append(folder)
            self.folders = try await self.service.folders(parent: folder.id)
            self.completed.removeAll()
        }
    }

    public func upload() {
        guard identity != nil, !snapshots.isEmpty else { return }
        run {
            self.isUploading = true
            defer { self.isUploading = false; self.progress = nil }
            self.statusMessage = nil
            self.failures.removeAll()
            let destination = self.destination
            for snapshot in self.snapshots where !self.completed.contains(snapshot.id) {
                try Task.checkCancellation()
                do {
                    try await self.service.upload(snapshot, to: destination) { update in
                        await self.receive(update)
                    }
                    self.completed.insert(snapshot.id)
                } catch is CancellationError { throw CancellationError() } catch {
                    self.failures[snapshot.id] = error.localizedDescription
                }
            }
            self.statusMessage = "Uploaded \(self.completed.count) of \(self.snapshots.count) meetings."
        }
    }

    public func cancel() {
        operation?.cancel()
    }

    public func close() async {
        operation?.cancel()
        await operation?.value
        await preparer.cleanup(snapshots)
        snapshots = []
    }

    private func receive(_ update: GoogleDriveBackupProgress) { progress = update }

    private func run(_ body: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        operation = Task {
            defer { self.isBusy = false }
            do { try await body() } catch is CancellationError {
                self.statusMessage =
                    "Cancelled. Uploaded files remain in Drive; local meetings are unchanged. You can retry."
            } catch { self.errorMessage = error.localizedDescription }
        }
    }
}
