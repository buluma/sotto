import Foundation
import Speech
import AVFoundation

private struct Inventory: Encodable {
    let available: Bool
    let supportedLocales: [String]
    let installedLocales: [String]
    let speechTranscriberAssetStatusByLocale: [String: String]
    let dictationTranscriberAssetStatusByLocale: [String: String]
    let note: String
}

private struct RecognitionResult: Encodable {
    let locale: String
    let assetStatus: String
    let sourceFile: String
    let transcript: String
    let note: String
}

@main
private enum LocaleInventory {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.first == "--developer-opt-in" else {
            fail("This developer-only probe requires --developer-opt-in. It never installs assets.")
        }

        guard #available(macOS 26.0, *) else {
            fail("Apple SpeechTranscriber locale inventory requires macOS 26 or later.")
        }

        do {
            switch arguments.dropFirst().first {
            case "--inventory" where arguments.count == 2:
                try await printInventory()
            case "--transcribe-file" where arguments.count == 4:
                try await transcribeFile(localeIdentifier: arguments[2], path: arguments[3])
            default:
                fail("Usage: LocaleInventory --developer-opt-in --inventory | --developer-opt-in --transcribe-file <locale> <audio-file>")
            }
        } catch {
            fail("Apple Speech probe failed: \(error)")
        }
    }

    @available(macOS 26.0, *)
    private static func printInventory() async throws {
        let supported = await SpeechTranscriber.supportedLocales
        let installed = await SpeechTranscriber.installedLocales
        var speechStatuses: [String: String] = [:]
        var dictationStatuses: [String: String] = [:]
        for locale in installed {
            let speechTranscriber = SpeechTranscriber(locale: locale, preset: .transcription)
            speechStatuses[locale.identifier] = String(
                describing: await AssetInventory.status(forModules: [speechTranscriber])
            )
            let dictationTranscriber = DictationTranscriber(locale: locale, preset: .shortDictation)
            dictationStatuses[locale.identifier] = String(
                describing: await AssetInventory.status(forModules: [dictationTranscriber])
            )
        }

        let result = Inventory(
            available: SpeechTranscriber.isAvailable,
            supportedLocales: supported.map(\.identifier).sorted(),
            installedLocales: installed.map(\.identifier).sorted(),
            speechTranscriberAssetStatusByLocale: speechStatuses,
            dictationTranscriberAssetStatusByLocale: dictationStatuses,
            note: "Inventory only; no assets were installed and no recognition session was started."
        )

        let data = try JSONEncoder().encode(result)
        print(String(decoding: data, as: UTF8.self))
    }

    @available(macOS 26.0, *)
    private static func transcribeFile(localeIdentifier: String, path: String) async throws {
        guard let locale = await SpeechTranscriber.installedLocales.first(where: { $0.identifier == localeIdentifier }) else {
            throw ProbeError.localeNotInstalled(localeIdentifier)
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let status = await AssetInventory.status(forModules: [transcriber])
        guard case .installed = status else {
            throw ProbeError.assetsNotInstalled(localeIdentifier, String(describing: status))
        }

        let fileURL = URL(fileURLWithPath: path)
        let audioFile = try AVAudioFile(forReading: fileURL)
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw ProbeError.noCompatibleAudioFormat
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let converter = AnalyzerInputConverter(analyzerFormat: analyzerFormat)
        let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)

        let resultTask = Task {
            var passages: [String] = []
            for try await result in transcriber.results {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { passages.append(text) }
            }
            return passages.joined(separator: " ")
        }

        do {
            var buffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: 8_192
            )!
            while true {
                try audioFile.read(into: buffer, frameCount: 8_192)
                if buffer.frameLength == 0 { break }
                for input in try converter.convert(buffer, at: nil) {
                    inputBuilder.yield(input)
                }
                buffer = AVAudioPCMBuffer(
                    pcmFormat: audioFile.processingFormat,
                    frameCapacity: 8_192
                )!
            }
            for input in try converter.flush() {
                inputBuilder.yield(input)
            }
            inputBuilder.finish()

            if let lastSampleTime = try await analyzer.analyzeSequence(inputSequence) {
                try await analyzer.finalizeAndFinish(through: lastSampleTime)
            } else {
                await analyzer.cancelAndFinishNow()
            }

            let result = RecognitionResult(
                locale: locale.identifier,
                assetStatus: String(describing: status),
                sourceFile: fileURL.lastPathComponent,
                transcript: try await resultTask.value,
                note: "Recognition completed with installed assets. Network access was not disabled, so this does not independently prove offline operation."
            )
            let data = try JSONEncoder().encode(result)
            print(String(decoding: data, as: UTF8.self))
        } catch {
            inputBuilder.finish()
            await analyzer.cancelAndFinishNow()
            resultTask.cancel()
            throw error
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        Foundation.exit(EXIT_FAILURE)
    }
}

private enum ProbeError: Error, CustomStringConvertible {
    case localeNotInstalled(String)
    case assetsNotInstalled(String, String)
    case noCompatibleAudioFormat

    var description: String {
        switch self {
        case .localeNotInstalled(let locale):
            return "locale \(locale) is not installed; this probe will not request installation"
        case .assetsNotInstalled(let locale, let status):
            return "assets for \(locale) are not installed (status: \(status)); this probe will not request installation"
        case .noCompatibleAudioFormat:
            return "SpeechAnalyzer did not provide a compatible audio format"
        }
    }
}
