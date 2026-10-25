import Foundation

public struct MeetingDriveBackupSource: Sendable {
    public let projection: SpeakerAttributionProjection
    public let promptResults: [PromptResult]
    public let classification: MeetingArtifactClassificationSnapshot?

    public init(
        projection: SpeakerAttributionProjection, promptResults: [PromptResult],
        classification: MeetingArtifactClassificationSnapshot? = nil
    ) {
        self.projection = projection
        self.promptResults = promptResults
        self.classification = classification
    }
}

public struct MeetingDriveBackupFile: Identifiable, Sendable {
    public var id: String { relativePath }
    public let relativePath: String
    public let url: URL
    public let size: Int64
}

public struct MeetingDriveBackupSnapshot: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let folder: URL
    public let files: [MeetingDriveBackupFile]
    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
}

/// Produces the exact, private staging copy reviewed by the user. Canonical
/// artifacts and database rows are never modified by backup preparation.
public actor MeetingDriveBackupPreparer {
    public init() {}

    public func prepare(_ sources: [MeetingDriveBackupSource]) async throws -> [MeetingDriveBackupSnapshot] {
        var snapshots: [MeetingDriveBackupSnapshot] = []
        do {
            for source in sources {
                try Task.checkCancellation()
                snapshots.append(try await prepare(source))
            }
            return snapshots
        } catch {
            cleanup(snapshots)
            throw error
        }
    }

    public func cleanup(_ snapshots: [MeetingDriveBackupSnapshot]) {
        for snapshot in snapshots {
            // Only our own staging directories may be removed.
            guard
                snapshot.folder.deletingLastPathComponent().standardizedFileURL
                    == FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL,
                snapshot.folder.lastPathComponent.hasPrefix("sotto-drive-backup-")
            else { continue }
            try? FileManager.default.removeItem(at: snapshot.folder)
        }
    }

    private func prepare(_ source: MeetingDriveBackupSource) async throws -> MeetingDriveBackupSnapshot {
        let fm = FileManager.default
        var transcription = source.projection.automaticTranscription
        guard transcription.sourceType == .meeting, transcription.status != .processing else {
            throw GoogleDriveError.message("Only saved meetings that have finished processing can be backed up.")
        }
        guard let original = MeetingArtifactStore.sessionFolderURL(for: transcription) else {
            throw MeetingArtifactError.missingSessionFolder
        }
        // No directory enumeration of the source: locks, scratch files, and
        // unrelated user files must never silently become upload candidates.
        let retainedNames = [
            "meeting-playback.m4a", "microphone-raw.m4a", "system-raw.m4a",
            "microphone-cleaned.m4a", "microphone.m4a", "system.m4a",
            "meeting-recording-metadata.json",
        ]
        let folder = fm.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("sotto-drive-backup-\(UUID().uuidString)")
        try fm.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            for name in retainedNames {
                try Task.checkCancellation()
                let from = original.appendingPathComponent(name)
                guard fm.fileExists(atPath: from.path) else { continue }
                // Reject symlinks, including a symlinked session folder.
                guard original.resolvingSymlinksInPath().standardizedFileURL == original.standardizedFileURL,
                    try from.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile == true,
                    try from.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true
                else { throw GoogleDriveError.message("A meeting artifact is not a regular local file.") }
                try fm.copyItem(at: from, to: folder.appendingPathComponent(name))
            }
            transcription.meetingArtifactFolderPath = folder.path
            transcription.filePath = transcription.filePath.map {
                folder.appendingPathComponent(URL(fileURLWithPath: $0).lastPathComponent).path
            }
            let projection = SpeakerAttributionProjection(
                automaticTranscription: transcription, attribution: source.projection.attribution,
                correctionsApplied: source.projection.correctionsApplied
            )
            _ = try await MeetingArtifactStore().materialize(
                projection: projection, promptResults: source.promptResults, classification: source.classification)
            // Keep canonical local path provenance rather than exposing the
            // temporary staging directory, which disappears on sheet close.
            for name in ["manifest.json", "transcript.json", "meeting.md"] {
                let url = folder.appendingPathComponent(name)
                if name.hasSuffix("json") {
                    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                    func restoringPaths(_ value: Any) -> Any {
                        if let text = value as? String {
                            return text.replacingOccurrences(of: folder.path, with: original.path)
                        }
                        if let values = value as? [String: Any] { return values.mapValues(restoringPaths) }
                        if let values = value as? [Any] { return values.map(restoringPaths) }
                        return value
                    }
                    try JSONSerialization.data(
                        withJSONObject: restoringPaths(object), options: [.prettyPrinted, .sortedKeys]
                    )
                    .write(to: url, options: .atomic)
                } else {
                    let text = try String(contentsOf: url).replacingOccurrences(of: folder.path, with: original.path)
                    try text.write(to: url, atomically: true, encoding: .utf8)
                }
            }
            try Task.checkCancellation()
            return MeetingDriveBackupSnapshot(
                id: transcription.id, title: transcription.fileName,
                folder: folder, files: try listFiles(in: folder))
        } catch {
            try? fm.removeItem(at: folder)
            throw error
        }
    }

    private func listFiles(in folder: URL) throws -> [MeetingDriveBackupFile] {
        guard let enumerator = FileManager.default.enumerator(atPath: folder.path) else {
            throw GoogleDriveError.message("The backup preview could not be prepared.")
        }
        var files: [MeetingDriveBackupFile] = []
        // Foundation's URL enumerator can return /private/var paths even
        // when resolvingSymlinksInPath() represents its root as /var. Use
        // the enumerator's relative names, never absolute-path slicing.
        for case let relativePath as String in enumerator {
            let url = folder.appendingPathComponent(relativePath)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true {
                files.append(
                    MeetingDriveBackupFile(
                        relativePath: relativePath,
                        url: url, size: Int64(values.fileSize ?? 0)))
            }
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }
}
