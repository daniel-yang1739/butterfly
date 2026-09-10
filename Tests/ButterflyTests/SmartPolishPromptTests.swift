import XCTest
@testable import ButterflyCore

final class SmartPolishPromptTests: XCTestCase {
    func testPromptProtectsTranscriptFidelity() {
        let prompt = SmartPolishPrompt.shared.content
        XCTAssertTrue(prompt.contains("Preserve every fact"))
        XCTAssertTrue(prompt.contains("Do not summarize"))
        XCTAssertTrue(prompt.contains("Taiwan Traditional Chinese"))
    }
}
