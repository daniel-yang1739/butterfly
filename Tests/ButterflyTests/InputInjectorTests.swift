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
    func testSkippedLargeRevisionPreservesActualCursorState() {
        let original = String(repeating: "a", count: 30)
        var previous = original
        XCTAssertEqual(injector.prepareStreamingDelta(newText: "short", previousText: &previous), .noChange)
        XCTAssertEqual(previous, original)
        XCTAssertEqual(injector.prepareStreamingDelta(newText: original + "!", previousText: &previous), .append(text: "!"))
    }

    func testLargeRevisionTracksOnlyInsertedSuffix() {
        let original = String(repeating: "a", count: 30)
        var previous = original
        let revised = String(repeating: "b", count: 31)
        XCTAssertEqual(injector.prepareStreamingDelta(newText: revised, previousText: &previous), .append(text: "b"))
        XCTAssertEqual(previous, original + "b")
    }

    func testFinalTranscriptReconcilesUnpublishedTail() {
        var previous = "Hello"
        XCTAssertEqual(injector.prepareStreamingDelta(newText: "Hello world.", previousText: &previous), .append(text: " world."))
        XCTAssertEqual(injector.prepareStreamingDelta(newText: "Hello world.", previousText: &previous), .noChange)
    }
}
