import XCTest
import SottoCore
@testable import Sotto

final class PromptManagementPresentationTests: XCTestCase {
    func testPromptLibraryOnlyIncludesTranscriptPromptsInEveryPresentation() {
        for presentation in [
            PromptLibraryPresentation.library,
            PromptLibraryPresentation.meetingAutoNotes,
        ] {
            XCTAssertTrue(presentation.includes(category: .result))
            XCTAssertFalse(presentation.includes(category: .transform))
            XCTAssertEqual(presentation.creationCategory, .result)
        }
    }
}
