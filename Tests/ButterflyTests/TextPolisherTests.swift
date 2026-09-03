import XCTest
@testable import ButterflyCore

final class TextPolisherTests: XCTestCase {
    var polisher: TextPolisher!
    
    override func setUp() {
        super.setUp()
        polisher = TextPolisher.shared
    }
    
    // MARK: - 1. Spoken Numbers & Metric/Digital Units
    
    func testSpokenNumbersToDigits() {
        let input = "我們大概需要八百多 MB 的空間，還有大概兩千行程式碼，第一點是速度，第二點是記憶體。"
        let output = polisher.polish(input, mode: .liveStream)
        
        XCTAssertTrue(output.contains("800 多 MB"), "Chinese numbers with units should be converted to digits: \(output)")
        XCTAssertTrue(output.contains("2000 行"), "Spoken thousands should be converted to digits: \(output)")
        XCTAssertTrue(output.contains("第 1 點"), "Quantifiers should use Arabic digits: \(output)")
        XCTAssertTrue(output.contains("第 2 點"), "Quantifiers should use Arabic digits: \(output)")
    }
    
    func testSpokenUnitsNormalization() {
        let input = "這個檔案大小是 500 Mega bite，另外一個備份是 2 Tara bite，重量是 5 kilogram。"
        let output = polisher.polish(input, mode: .liveStream)
        
        XCTAssertTrue(output.contains("500 MB"), "Mega bite should normalize to MB: \(output)")
        XCTAssertTrue(output.contains("2 TB"), "Tara bite should normalize to TB: \(output)")
        XCTAssertTrue(output.contains("5 kg"), "kilogram should normalize to kg: \(output)")
    }
    
    // MARK: - 2. Faithful Streaming & Natural Formatting
    
    func testLiveStreamFaithfulPreservation() {
        let input = "好，我們測試一下。測試測試看起來好像沒有什麼問題喔，那標點符號在嗎？"
        let output = polisher.polish(input, mode: .liveStream)
        
        // Faithful preservation of natural speech
        XCTAssertTrue(output.contains("測試測試"), "Must preserve consecutive repeated words: \(output)")
        XCTAssertTrue(output.contains("，"), "Must preserve commas: \(output)")
        XCTAssertTrue(output.contains("？"), "Must preserve question marks: \(output)")
    }
    
    func testTraditionalChinesePassThrough() {
        let input = "这是即时语音听写的测试"
        let output = polisher.polish(input, mode: .liveStream)
        XCTAssertEqual(output, "這是即時語音聽寫的測試")
    }
}
