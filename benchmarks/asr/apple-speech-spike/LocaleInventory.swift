import Foundation
import Speech

private struct Inventory: Encodable {
    let available: Bool
    let supportedLocales: [String]
    let installedLocales: [String]
    let note: String
}

@main
private enum LocaleInventory {
    static func main() async {
        guard CommandLine.arguments == [CommandLine.arguments[0], "--developer-opt-in", "--inventory"] else {
            FileHandle.standardError.write(Data("This developer-only probe requires --developer-opt-in --inventory. It does not install assets or start recognition.\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }

        guard #available(macOS 26.0, *) else {
            FileHandle.standardError.write(Data("Apple SpeechTranscriber locale inventory requires macOS 26 or later.\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }

        let supported = await SpeechTranscriber.supportedLocales
        let installed = await SpeechTranscriber.installedLocales
        let result = Inventory(
            available: SpeechTranscriber.isAvailable,
            supportedLocales: supported.map(\.identifier).sorted(),
            installedLocales: installed.map(\.identifier).sorted(),
            note: "Inventory only; no assets were installed and no recognition session was started."
        )

        do {
            let data = try JSONEncoder().encode(result)
            print(String(decoding: data, as: UTF8.self))
        } catch {
            FileHandle.standardError.write(Data("Could not encode locale inventory: \(error)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
