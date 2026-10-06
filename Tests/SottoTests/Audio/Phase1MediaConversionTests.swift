import AVFoundation
import Foundation
import XCTest
@testable import SottoCore

/// Opt-in qualification with generated one-second tone fixtures, never user media.
final class Phase1MediaConversionTests: XCTestCase {
    func testPlannedFormatsPreserveAudioThroughConversion() async throws {
        guard let path = ProcessInfo.processInfo.environment["SOTTO_PHASE1_MEDIA_FIXTURES"] else {
            throw XCTSkip("Set SOTTO_PHASE1_MEDIA_FIXTURES to the synthetic qualification fixture directory")
        }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let converter = AudioFileConverter()
        for ext in ["m4a", "mp3", "wav", "mp4", "mov"] {
            let input = root.appendingPathComponent("fixture.\(ext)")
            let output = try await converter.convert(fileURL: input)
            defer { try? FileManager.default.removeItem(at: output) }
            let file = try AVAudioFile(forReading: output)
            XCTAssertEqual(file.processingFormat.sampleRate, 16_000, ext)
            XCTAssertEqual(file.processingFormat.channelCount, 1, ext)
            XCTAssertGreaterThanOrEqual(file.length, 14_400, ext)
            XCTAssertLessThanOrEqual(file.length, 18_400, ext)
            let buffer = try XCTUnwrap(
                AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_096)
            )
            try file.read(into: buffer)
            let samples = try XCTUnwrap(buffer.floatChannelData)
            let peak = (0..<Int(buffer.frameLength)).map { abs(samples[0][$0]) }.max() ?? 0
            XCTAssertGreaterThan(peak, 0.01, "\(ext) lost the synthetic tone")
            XCTAssertTrue(FileManager.default.fileExists(atPath: input.path), "\(ext) input removed")
        }
        do {
            _ = try await converter.convert(fileURL: root.appendingPathComponent("fixture.aac"))
            XCTFail("Raw AAC is currently outside the supported extension contract")
        } catch AudioProcessorError.unsupportedFormat(let ext) {
            XCTAssertEqual(ext, "aac")
        }
    }
}
