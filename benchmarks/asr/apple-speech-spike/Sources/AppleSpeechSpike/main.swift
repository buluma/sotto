import Foundation
import SottoCore

@main
struct AppleSpeechSpike {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 4,
            arguments[0] == "--developer-opt-in",
            arguments[1] == "--transcribe-file"
        else {
            fputs("Usage: AppleSpeechSpike --developer-opt-in --transcribe-file <locale> <audio-path>\n", stderr)
            exit(64)
        }

        guard #available(macOS 26.0, *) else {
            fputs("Apple SpeechTranscriber spike requires macOS 26 or later.\n", stderr)
            exit(69)
        }

        do {
            let scheduler = STTScheduler()
            let result = try await scheduler.transcribeAppleSpeechSpike(
                audioPath: arguments[3],
                localeIdentifier: arguments[2]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let output = Output(text: result.text, session: result.snapshot)
            FileHandle.standardOutput.write(try encoder.encode(output))
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            fputs("Apple Speech spike failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private struct Output: Encodable {
        let text: String
        let session: AppleSpeechSessionSnapshot
    }
}
