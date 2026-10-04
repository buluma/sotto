import SottoCore
import SottoViewModels
import XCTest
@testable import Sotto

final class TranscriptResultTabOrderingTests: XCTestCase {
    func testMeetingStartsWithTranscriptThenNotes() {
        XCTAssertEqual(
            TranscriptResultTabOrdering.leadingTabs(for: .meeting),
            [.transcript, .notes]
        )
    }

    func testNonMeetingDoesNotExposeNotesTab() {
        XCTAssertEqual(
            TranscriptResultTabOrdering.leadingTabs(for: .file),
            [.transcript]
        )
    }
}
