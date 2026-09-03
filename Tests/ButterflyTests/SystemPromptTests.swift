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
}
