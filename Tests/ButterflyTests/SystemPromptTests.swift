import XCTest
@testable import ButterflyCore

final class SystemPromptTests: XCTestCase {
    func testSystemPromptLoadingAndFallback() {
        let content = SystemPrompt.shared.content
        XCTAssertFalse(content.isEmpty, "System Prompt content must not be empty")
        XCTAssertTrue(content.contains("Butterfly"), "System Prompt must mention Butterfly role")
    }
    
    func testSystemPromptReloading() {
        SystemPrompt.shared.reload()
        let content = SystemPrompt.shared.content
        XCTAssertFalse(content.isEmpty)
    }

    func testSmartPolishPromptProtectsTranscriptFidelity() {
        let prompt = SmartPolishPrompt.shared.content
        XCTAssertTrue(prompt.contains("Preserve every fact"))
        XCTAssertTrue(prompt.contains("Do not summarize"))
        XCTAssertTrue(prompt.contains("Taiwan Traditional Chinese"))
    }
}
