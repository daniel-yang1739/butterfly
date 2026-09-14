import XCTest
import ButterflyTestSupport

final class StateMachineTests: XCTestCase {
    @MainActor
    func testProductionCoordinatorWithoutMicrophoneOrKeyboardEvents() async {
        for check in await DictationRegressionSuite.coordinator() {
            XCTAssertTrue(check.passed, check.name)
        }
    }

    @MainActor
    func testRecognitionFinalizationAndSessionIsolation() async {
        for check in await DictationRegressionSuite.recognition() {
            XCTAssertTrue(check.passed, check.name)
        }
    }

    @MainActor
    func testSilenceDoesNotScheduleHallucinatedContinuations() {
        for check in DictationRegressionSuite.audio() {
            XCTAssertTrue(check.passed, check.name)
        }
    }
}
