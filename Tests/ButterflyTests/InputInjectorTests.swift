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
        
        injector.injectStreamingDelta(newText: newText, previousText: &previous)
        XCTAssertEqual(previous, "你好世界", "Previous text should be updated to new text")
    }
    
    func testStreamingDeltaInPlaceCorrection() {
        var previous = "你好是界"
        let newText = "你好世界"
        
        injector.injectStreamingDelta(newText: newText, previousText: &previous)
        XCTAssertEqual(previous, "你好世界", "In-place corrected text should become new text")
    }
}
