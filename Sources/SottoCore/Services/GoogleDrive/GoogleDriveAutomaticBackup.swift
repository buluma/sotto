import Foundation
import OSLog

/// Durable work and receipts for the explicitly selected account and destination.
/// Local meeting artifacts remain the source of truth and are staged on demand.
public actor GoogleDriveAutomaticBackup {
    public static let shared = GoogleDriveAutomaticBackup()

    public struct Candidate: Codable, Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let revision: String
        public let changedAt: Date

        public init(id: UUID, title: String, revision: String, changedAt: Date) {
            self.id = id
            self.title = title
            self.revision = revision
            self.changedAt = changedAt
        }
    }

    public struct Configuration: Codable, Equatable, Sendable {
        let generation: UUID
        let enabledAt: Date
        public let identity: GoogleDriveIdentity
        public let destination: GoogleDriveFolder
        public fileprivate(set) var paused: Bool
    }

    public struct Entry: Codable, Identifiable, Sendable {
        public enum Phase: String, Codable, Sendable {
            case pending, uploaded, signInRequired, failed
        }

        public var id: UUID { candidate.id }
        public let candidate: Candidate
        public fileprivate(set) var phase = Phase.pending
        public fileprivate(set) var message: String?
        var attempts = 0
        var retryAt: Date?
    }

    public struct Status: Codable, Sendable {
        public fileprivate(set) var configuration: Configuration?
        var records: [UUID: Entry] = [:]
        public var entries: [Entry] {
            records.values.sorted { $0.candidate.changedAt > $1.candidate.changedAt }
        }
    }

    private static let logger = Logger(subsystem: "com.sotto", category: "GoogleDriveBackup")
    /// Unclassified failures (Keychain, staging I/O, local locks) are often
    /// short-lived, so they retry with backoff before needing an explicit Retry.
    static let maxUnclassifiedAttempts = 5

    private let queueURL: URL
    private let account: GoogleDriveAccount
    private let uploader: any GoogleDriveBackingUp
    private let preparer: MeetingDriveBackupPreparer
    private var active = false

    public init(
        queueURL: URL? = nil, account: GoogleDriveAccount = .shared,
        uploader: any GoogleDriveBackingUp = GoogleDriveBackupService.shared,
        preparer: MeetingDriveBackupPreparer = MeetingDriveBackupPreparer()
    ) {
        self.queueURL =
            queueURL
            ?? URL(fileURLWithPath: AppPaths.appSupportDir)
            .appendingPathComponent("google-drive-automatic-backup.json")
        self.account = account
        self.uploader = uploader
        self.preparer = preparer
    }

    public func status() throws -> Status {
        do {
            return try read()
        } catch is DecodingError {
            let lock = try GoogleDriveFileLock(url: queueURL.appendingPathExtension("lock"), nonblocking: false)
            defer { lock.release() }
            return try readSettingAsideUndecodable()
        }
    }

    public func enable(identity: GoogleDriveIdentity, destination: GoogleDriveFolder, now: Date = Date()) throws {
        try update { state in
            if let config = state.configuration, config.identity == identity, config.destination.id == destination.id {
                state.configuration?.paused = false
                return
            }
            state = Status(
                configuration: Configuration(
                    generation: UUID(), enabledAt: now, identity: identity, destination: destination, paused: false))
        }
    }

    public func setPaused(_ paused: Bool) throws {
        try update { $0.configuration?.paused = paused }
    }

    public func disable() throws {
        try update { $0 = Status() }
    }

    public func retry(_ id: UUID) throws {
        try update { state in
            // Pending entries may be waiting out a backoff that Retry must not reset.
            guard let entry = state.records[id], entry.phase == .failed || entry.phase == .signInRequired
            else { return }
            state.records[id] = Entry(candidate: entry.candidate)
        }
    }

    public func discover(_ candidates: [Candidate]) throws {
        try update { state in
            guard let config = state.configuration else { return }
            // Receipts for meetings that no longer exist locally would otherwise
            // accumulate forever. Unfinished work is removed by the worker.
            let current = Set(candidates.map(\.id))
            state.records = state.records.filter { $0.value.phase != .uploaded || current.contains($0.key) }
            for candidate in candidates {
                let prior = state.records[candidate.id]
                guard (prior != nil || candidate.changedAt >= config.enabledAt),
                    prior?.candidate.revision != candidate.revision,
                    prior.map({ $0.candidate.changedAt <= candidate.changedAt }) ?? true
                else { continue }
                state.records[candidate.id] = Entry(candidate: candidate)
            }
        }
    }

    /// Attempts one eligible entry. A process exit leaves it pending, and the
    /// uploader reuses its Drive IDs when the worker restages it on restart.
    public func uploadNext(
        now: Date? = nil, source: @Sendable (UUID) async throws -> MeetingDriveBackupSource?
    ) async throws -> Bool {
        guard !active else { return false }
        active = true
        defer { active = false }
        let lease: GoogleDriveFileLock
        do {
            lease = try GoogleDriveFileLock(url: queueURL.appendingPathExtension("worker.lock"), nonblocking: true)
        } catch GoogleDriveError.busy {
            return false
        }
        defer { lease.release() }
        let state = try status()
        let eligibilityTime = now ?? Date()
        guard let config = state.configuration, !config.paused,
            var entry = state.entries.reversed().first(where: {
                $0.phase == .pending && ($0.retryAt ?? .distantPast) <= eligibilityTime
            })
        else { return false }
        // The account is shared by every entry. An unreadable Keychain or a
        // disconnected or different account holds the queue instead of
        // recording the same failure on each entry in turn.
        guard try await account.identity() == config.identity else { return false }
        do {
            guard let current = try await source(entry.id) else {
                try save(nil, replacing: entry, configuration: config)
                return true
            }
            let snapshots = try await preparer.prepare([current])
            do {
                let latest = try status()
                // Pausing lets this staged upload finish; only a new generation
                // (turned off, or a different account or destination) drops it.
                guard latest.configuration?.generation == config.generation,
                    latest.records[entry.id]?.candidate == entry.candidate
                else {
                    await preparer.cleanup(snapshots)
                    return false
                }
                for snapshot in snapshots {
                    try await uploader.upload(snapshot, to: config.destination, identity: config.identity) { _ in }
                }
            } catch {
                await preparer.cleanup(snapshots)
                throw error
            }
            await preparer.cleanup(snapshots)
            entry.phase = .uploaded
            entry.message = nil
            entry.retryAt = nil
        } catch {
            try Task.checkCancellation()
            let failure =
                error is CancellationError
                ? GoogleDriveError.authenticationRequired("Reconnect the Google account selected for automatic backup.")
                : error
            Self.record(failure, on: &entry, now: now ?? Date())
        }
        try save(entry, replacing: entry, configuration: config)
        return true
    }

    private func save(_ entry: Entry?, replacing previous: Entry, configuration: Configuration) throws {
        try update { state in
            guard state.configuration?.generation == configuration.generation,
                state.records[previous.id]?.candidate == previous.candidate
            else { return }
            state.records[previous.id] = entry
        }
    }

    private func update(_ change: (inout Status) -> Void) throws {
        let lock = try GoogleDriveFileLock(url: queueURL.appendingPathExtension("lock"), nonblocking: false)
        defer { lock.release() }
        var state = try readSettingAsideUndecodable()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let previous = try encoder.encode(state)
        change(&state)
        let data = try encoder.encode(state)
        guard data != previous else { return }
        try data.write(to: queueURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: queueURL.path)
    }

    private func read() throws -> Status {
        guard FileManager.default.fileExists(atPath: queueURL.path) else { return Status() }
        return try JSONDecoder().decode(Status.self, from: Data(contentsOf: queueURL))
    }

    /// Callers hold the queue lock. An undecodable queue (truncated, or from an
    /// incompatible build) would otherwise block every control, including
    /// Turn off, so its bytes are kept aside and automatic backup reads as off.
    private func readSettingAsideUndecodable() throws -> Status {
        do {
            return try read()
        } catch is DecodingError {
            let aside = queueURL.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.removeItem(at: aside)
            try FileManager.default.moveItem(at: queueURL, to: aside)
            Self.logger.error("Set aside an unreadable automatic Drive backup queue; automatic backup is off.")
            return Status()
        }
    }

    private static func record(_ error: Error, on entry: inout Entry, now: Date) {
        entry.attempts += 1
        entry.message = (error as? GoogleDriveError)?.errorDescription ?? "The meeting backup could not be completed."
        switch error {
        case GoogleDriveError.authenticationRequired, GoogleDriveError.http(401), GoogleDriveError.api(401, _, _):
            entry.phase = .signInRequired
        case GoogleDriveError.busy:
            entry.retryAt = now.addingTimeInterval(30)
        case let error as URLError:
            if [
                .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
                .cannotFindHost, .dnsLookupFailed,
            ].contains(error.code) {
                entry.message = "Waiting for a connection to Google Drive."
                entry.retryAt = nextRetry(attempts: entry.attempts, now: now)
            } else {
                entry.phase = .failed
            }
        case GoogleDriveError.api(403, _, "rateLimitExceeded"), GoogleDriveError.api(403, _, "userRateLimitExceeded"):
            entry.retryAt = nextRetry(attempts: entry.attempts, now: now)
        case GoogleDriveError.http(let status), GoogleDriveError.api(let status, _, _):
            if status == 408 || status == 429 || (500..<600).contains(status) {
                entry.retryAt = nextRetry(attempts: entry.attempts, now: now)
            } else {
                entry.phase = .failed
            }
        default:
            if entry.attempts < maxUnclassifiedAttempts {
                entry.retryAt = nextRetry(attempts: entry.attempts, now: now)
            } else {
                entry.phase = .failed
            }
        }
    }

    private static func nextRetry(attempts: Int, now: Date) -> Date {
        now.addingTimeInterval(min(900, 15 * pow(2, Double(min(attempts - 1, 6)))))
    }
}
