import Foundation
import SottoCore

enum TranscriptionDeletionCleanup {
    static func removeOwnedAssets(for transcription: Transcription) throws {
        try TranscriptionAssetCleanup.removeOwnedAssets(for: transcription)
    }

    @discardableResult
    static func removeOwnedMeetingAudio(for transcription: Transcription) throws -> Bool {
        try TranscriptionAssetCleanup.removeOwnedMeetingAudio(for: transcription)
    }
}
