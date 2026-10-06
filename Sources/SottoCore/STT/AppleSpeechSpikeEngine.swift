#if DEBUG
import AVFoundation
import Foundation
import Speech

public struct AppleSpeechSessionSnapshot: Codable, Equatable, Sendable {
    public let id: UUID
    public let localeIdentifier: String
    public let moduleIdentifier: String
    public let presetIdentifier: String
    public let operatingSystemVersion: String
    public let assetStatusBeforeRequest: String
    public let assetStatusAfterRequest: String
    public let assetInstallationRequestWasNil: Bool
    /// Apple does not expose a model asset revision for this module.
    public let assetRevision: String?
    public let createdAt: Date
}

public struct AppleSpeechSpikeResult: Sendable {
    public let text: String
    public let snapshot: AppleSpeechSessionSnapshot

    public init(text: String, snapshot: AppleSpeechSessionSnapshot) {
        self.text = text
        self.snapshot = snapshot
    }
}

enum AppleSpeechSpikeError: Error, LocalizedError {
    case unavailable
    case unsupportedLocale(String)
    case assetsNotInstalled(locale: String, status: String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Apple SpeechTranscriber is unavailable on this Mac."
        case .unsupportedLocale(let locale):
            "Apple SpeechTranscriber does not support locale \(locale)."
        case .assetsNotInstalled(let locale, let status):
            "Apple SpeechTranscriber assets for \(locale) are not installed (status: \(status)); no download was started."
        }
    }
}

actor AppleSpeechSpikeEngine {
    @available(macOS 26.0, *)
    func transcribeFile(audioPath: String, localeIdentifier: String) async throws -> AppleSpeechSpikeResult {
        try Task.checkCancellation()
        guard SpeechTranscriber.isAvailable else {
            throw AppleSpeechSpikeError.unavailable
        }

        let supportedLocales = await SpeechTranscriber.supportedLocales
        guard let locale = supportedLocales.first(where: { $0.identifier == localeIdentifier }) else {
            throw AppleSpeechSpikeError.unsupportedLocale(localeIdentifier)
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let statusBeforeRequest = await AssetInventory.status(forModules: [transcriber])
        let installationRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
        guard installationRequest == nil else {
            throw AppleSpeechSpikeError.assetsNotInstalled(
                locale: localeIdentifier,
                status: String(describing: statusBeforeRequest)
            )
        }
        let statusAfterRequest = await AssetInventory.status(forModules: [transcriber])

        let snapshot = AppleSpeechSessionSnapshot(
            id: UUID(),
            localeIdentifier: locale.identifier,
            moduleIdentifier: "SpeechTranscriber",
            presetIdentifier: "transcription",
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            assetStatusBeforeRequest: String(describing: statusBeforeRequest),
            assetStatusAfterRequest: String(describing: statusAfterRequest),
            assetInstallationRequestWasNil: true,
            assetRevision: nil,
            createdAt: Date()
        )

        let audioFile = try AVAudioFile(forReading: URL(fileURLWithPath: audioPath))
        let resultTask = Task {
            var passages: [String] = []
            for try await result in transcriber.results {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    passages.append(text)
                }
            }
            return passages.joined(separator: " ")
        }

        do {
            let analyzer = try await SpeechAnalyzer(
                inputAudioFile: audioFile,
                modules: [transcriber],
                finishAfterFile: true
            )
            let text = try await withTaskCancellationHandler {
                try await resultTask.value
            } onCancel: {
                resultTask.cancel()
                Task {
                    await analyzer.cancelAndFinishNow()
                }
            }
            try Task.checkCancellation()
            return AppleSpeechSpikeResult(text: text, snapshot: snapshot)
        } catch {
            resultTask.cancel()
            throw error
        }
    }
}
#endif
