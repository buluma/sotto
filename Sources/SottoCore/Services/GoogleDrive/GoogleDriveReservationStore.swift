import Darwin
import Foundation

/// Atomic replacement protects readers; the OS lock protects read/merge/write
/// transactions across app instances. Never keep a process-local ledger cache.
struct GoogleDriveReservationStore: Sendable {
    let url: URL

    func read() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    func reserve(_ key: String, generatedID: String) throws -> String {
        let lock = try GoogleDriveFileLock(url: url.appendingPathExtension("lock"), nonblocking: false)
        defer { lock.release() }
        var values = try read()
        if let existing = values[key] { return existing }
        values[key] = generatedID
        try JSONEncoder().encode(values).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return generatedID
    }

    func acquireUploadLease() throws -> GoogleDriveFileLock {
        try GoogleDriveFileLock(url: url.appendingPathExtension("upload.lock"), nonblocking: true)
    }
}

/// The descriptor keeps the lock through awaited upload work and is released
/// by the kernel on process exit. Each lease has a single actor-local owner.
final class GoogleDriveFileLock {
    private var descriptor: Int32?

    init(url: URL, nonblocking: Bool) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else {
            throw GoogleDriveError.message("The local Google Drive backup lock could not be opened.")
        }
        guard flock(descriptor, LOCK_EX | (nonblocking ? LOCK_NB : 0)) == 0 else {
            Darwin.close(descriptor)
            throw GoogleDriveError.message(
                "Another Sotto instance is backing up to Google Drive. Retry when it finishes.")
        }
        self.descriptor = descriptor
    }

    deinit { release() }

    func release() {
        guard let descriptor else { return }
        self.descriptor = nil
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
    }
}
