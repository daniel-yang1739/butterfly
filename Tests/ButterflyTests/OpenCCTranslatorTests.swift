import XCTest
@testable import ButterflyCore

final class OpenCCTranslatorTests: XCTestCase {
    var translator: OpenCCTranslator!
    
    override func setUp() {
        super.setUp()
        translator = OpenCCTranslator.shared
    }
    
    // TC-A1: Pure Simplified Chinese conversion test
    func testPureSimplifiedConversion() {
        let input = "这是语音识别测试"
        let expected = "這是語音識別測試"
        let output = translator.convert(input)
        XCTAssertEqual(output, expected)
        XCTAssertFalse(translator.containsSimplified(output))
    }
    
    // TC-A2: Taiwan vocabulary adaptation test
    func testTaiwanLexiconAdaptation() {
        let input = "服务器内存不足，请更新数据库与界面代码，使用默认设置"
        let expected = "伺服器記憶體不足，請更新資料庫與介面程式碼，使用預設設定"
        let output = translator.convert(input)
        XCTAssertEqual(output, expected)
        XCTAssertFalse(translator.containsSimplified(output))
    }
    
    // TC-A3: Mixed Chinese and English code-switching conversion test
    func testMixedChineseAndEnglishConversion() {
        let input = "请帮我review这段React代码，并提交一个PR"
        let expected = "請幫我review這段React程式碼，並提交一個PR"
        let output = translator.convert(input)
        XCTAssertEqual(output, expected)
        XCTAssertFalse(translator.containsSimplified(output))
    }
    
    // TC-A4: Pure English case and token preservation test
    func testPureEnglishPreservation() {
        let input = "git checkout -b feature/butterfly --quiet"
        let output = translator.convert(input)
        XCTAssertEqual(output, input)
    }
    
    // TC-A5: Special symbols, URLs, and numbers preservation test
    func testSpecialCharactersAndURLs() {
        let input = "API version is v2.0, URL is https://example.com/api?id=123"
        let output = translator.convert(input)
        XCTAssertTrue(output.contains("https://example.com/api?id=123"))
        XCTAssertTrue(output.contains("v2.0"))
    }
    
    // TC-A6: Zero Simplified Chinese residual assertion
    func testZeroSimplifiedResidualAssertion() {
        let testCorpus = [
            "这是测试",
            "人工智能深度学习与神经网络模型",
            "在终端机上运行命令行工具",
            "优化性能与内存管理",
            "创建新的分支并发布版本"
        ]
        
        for text in testCorpus {
            let converted = translator.convert(text)
            XCTAssertFalse(translator.containsSimplified(converted), "Conversion output must not contain Simplified Chinese: \(converted)")
        }
    }
}
