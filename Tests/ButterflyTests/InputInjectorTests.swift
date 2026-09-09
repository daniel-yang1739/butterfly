import XCTest
@testable import ButterflyCore

final class InputInjectorTests: XCTestCase {
    var injector: InputInjector!
    
    override func setUp() {
        super.setUp()
        injector = InputInjector.shared
    }
    
    func testStreamingDeltaDirectAppend() {
        var previous = "你好"
        let newText = "你好世界"
        
        let action = injector.prepareStreamingDelta(newText: newText, previousText: &previous)
        XCTAssertEqual(previous, "你好世界", "Previous text should be updated to new text")
        XCTAssertEqual(action, .append(text: "世界"))
    }
    
    func testStreamingDeltaInPlaceCorrection() {
        var previous = "你好是界"
        let newText = "你好世界"
        
        let action = injector.prepareStreamingDelta(newText: newText, previousText: &previous)
        XCTAssertEqual(previous, "你好世界", "In-place corrected text should become new text")
        XCTAssertEqual(action, .replaceTail(backspaces: 2, replacement: "世界"))
    }
    func testLargeRevisionCanShortenTheTranscript() {
        let original = String(repeating: "a", count: 30)
        var previous = original
        XCTAssertEqual(injector.prepareStreamingDelta(newText: "short", previousText: &previous), .replaceTail(backspaces: 30, replacement: "short"))
        XCTAssertEqual(previous, "short")
        XCTAssertEqual(injector.prepareStreamingDelta(newText: "short!", previousText: &previous), .append(text: "!"))
    }

    func testLargeRevisionReplacesTheActualTail() {
        let original = String(repeating: "a", count: 30)
        var previous = original
        let revised = String(repeating: "b", count: 31)
        XCTAssertEqual(injector.prepareStreamingDelta(newText: revised, previousText: &previous), .replaceTail(backspaces: 30, replacement: revised))
        XCTAssertEqual(previous, revised)
    }

    func testFinalTranscriptReconcilesUnpublishedTail() {
        var previous = "Hello"
        XCTAssertEqual(injector.prepareStreamingDelta(newText: "Hello world.", previousText: &previous), .append(text: " world."))
        XCTAssertEqual(injector.prepareStreamingDelta(newText: "Hello world.", previousText: &previous), .noChange)
    }
}
