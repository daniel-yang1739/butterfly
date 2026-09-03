import XCTest
@testable import ButterflyCore

final class TextFormatterTests: XCTestCase {
    var formatter: TextFormatter!
    
    override func setUp() {
        super.setUp()
        formatter = TextFormatter.shared
    }
    
    // TC-B1: CJK and alphanumeric spacing test (Pangu Spacing)
    func testCJKAndAlphanumericSpacing() {
        let input = "建立一個React組件與10個API端點"
        let expected = "建立一個 React 組件與 10 個 API 端點"
        let output = formatter.insertSpacingBetweenCJKAndAlphanumeric(input)
        XCTAssertEqual(output, expected)
    }
    
    // TC-B2: Trailing punctuation trimming test
    func testTrailingPunctuationTrimming() {
        let input1 = "今天天氣真好。"
        let output1 = formatter.trimTrailingPunctuationIfNeeded(input1)
        XCTAssertEqual(output1, "今天天氣真好")
        
        let input2 = "請幫我確認這段程式碼，"
        let output2 = formatter.trimTrailingPunctuationIfNeeded(input2)
        XCTAssertEqual(output2, "請幫我確認這段程式碼")
    }
    
    // TC-B3: Stutter deduplication test
    func testStutterDeduplication() {
        let input1 = "我我我覺得可以"
        let output1 = formatter.deduplicateStutter(input1)
        XCTAssertEqual(output1, "我覺得可以")
        
        let input2 = "這這這個問題"
        let output2 = formatter.deduplicateStutter(input2)
        XCTAssertEqual(output2, "這個問題")
    }
    
    // TC-B4: Multi-utterance transcript join with natural punctuation
    func testMultiUtteranceJoin() {
        let engine = LiveSpeechEngine.shared
        let parts = ["今天天氣真好", "我想去公園散步", "順便買杯咖啡"]
        let joined = engine.joinTranscripts(parts)
        XCTAssertEqual(joined, "今天天氣真好，我想去公園散步，順便買杯咖啡")
        XCTAssertFalse(joined.hasPrefix(" "))
    }
    
    // TC-B5: Multi-utterance English join with appropriate spaces
    func testEnglishUtteranceJoin() {
        let engine = LiveSpeechEngine.shared
        let parts = ["Hello", "world", "this is Butterfly"]
        let joined = engine.joinTranscripts(parts)
        XCTAssertEqual(joined, "Hello world this is Butterfly")
        XCTAssertFalse(joined.hasPrefix(" "))
    }
    
    // Full formatting pipeline test
    func testFullFormattingPipeline() {
        let input = "我我我想建立一個React組件。"
        let expected = "我想建立一個 React 組件"
        let output = formatter.format(input)
        XCTAssertEqual(output, expected)
    }
}
