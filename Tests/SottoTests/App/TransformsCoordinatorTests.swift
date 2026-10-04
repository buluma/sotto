import XCTest
@testable import Sotto
import SottoCore

@MainActor
final class TransformsCoordinatorTests: XCTestCase {
    func testActiveModelIsSnapshottedBeforeAQueuedTransformCanObserveConfigChange() {
        var activeModel = "model-before-queue"

        let snapshot = TransformsCoordinator.resolveModelSnapshot(
            promptOverride: nil,
            activeModelName: activeModel
        )
        activeModel = "model-after-queue"

        XCTAssertEqual(snapshot, "model-before-queue")
        XCTAssertEqual(activeModel, "model-after-queue")
    }

    func testPromptModelOverrideWinsOverActiveModelSnapshot() {
        XCTAssertEqual(
            TransformsCoordinator.resolveModelSnapshot(
                promptOverride: " prompt-model ",
                activeModelName: "global-model"
            ),
            "prompt-model"
        )
    }

    func testMenuCaptureMustBelongToMenuOpenApp() {
        let menuOpenTarget = SelectionCaptureTarget(
            processIdentifier: 99,
            bundleIdentifier: "com.apple.mail"
        )
        let otherTarget = SelectionCaptureTarget(
            processIdentifier: 1234,
            bundleIdentifier: "com.example.Other"
        )
        let captured = SelectionCaptureResult.clipboard(
            text: "Other app selection",
            savedClipboard: .none,
            target: otherTarget
        )

        XCTAssertFalse(TransformsCoordinator.menuCaptureBelongsToTarget(captured, target: menuOpenTarget))
        XCTAssertFalse(TransformsCoordinator.menuCaptureBelongsToTarget(captured, target: nil))
        XCTAssertTrue(TransformsCoordinator.menuCaptureBelongsToTarget(captured, target: otherTarget))
    }

    func testMenuCaptureUsesOnlyTheAppObservedAtStatusButtonMouseDown() {
        let safari = SelectionCaptureTarget(
            processIdentifier: 99,
            bundleIdentifier: "com.apple.Safari"
        )
        let sotto = SelectionCaptureTarget(
            processIdentifier: 1234,
            bundleIdentifier: "com.sotto"
        )

        XCTAssertEqual(
            TransformsCoordinator.menuCaptureTarget(
                frontmostApplication: safari,
                ownBundleIdentifier: sotto.bundleIdentifier
            )?.processIdentifier,
            safari.processIdentifier
        )
        // Safari may have been frontmost earlier, but opening the menu while
        // Sotto is active must not reuse that stale foreign target.
        XCTAssertNil(
            TransformsCoordinator.menuCaptureTarget(
                frontmostApplication: sotto,
                ownBundleIdentifier: sotto.bundleIdentifier
            )
        )
        XCTAssertNil(
            TransformsCoordinator.menuCaptureTarget(
                frontmostApplication: nil,
                ownBundleIdentifier: sotto.bundleIdentifier
            )
        )
    }

    func testMenuCaptureWaitsForExactFrontmostProcess() async {
        let target = SelectionCaptureTarget(processIdentifier: 99, bundleIdentifier: "com.apple.Safari")
        let otherProcess = SelectionCaptureTarget(processIdentifier: 1234, bundleIdentifier: target.bundleIdentifier)
        let otherBundle = SelectionCaptureTarget(processIdentifier: target.processIdentifier, bundleIdentifier: "other")
        var observations = [otherProcess, otherBundle, target]

        let activated = await TransformsCoordinator.waitForMenuCaptureTarget(
            target,
            timeout: .seconds(1),
            pollInterval: .milliseconds(1)
        ) {
            observations.removeFirst()
        }

        XCTAssertTrue(activated)
        XCTAssertTrue(observations.isEmpty)
        let rejected = await TransformsCoordinator.waitForMenuCaptureTarget(
            target,
            timeout: .zero
        ) {
            otherProcess
        }
        XCTAssertFalse(rejected)
    }
}
