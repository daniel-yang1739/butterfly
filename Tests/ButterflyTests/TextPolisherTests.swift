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
    
    // MARK: - 2. Tech Terms & Fuzzy Phonetic Restoration
    
    func testMode1AndMode2FuzzyVariations() {
        let corpusMode1 = [
            "我們現在在用 茂 the one 測試",
            "切換到 沒ode 1 試試看",
            "這個是 ml 的 one 模式",
            "測試 莫德萬 的效果"
        ]
        for sentence in corpusMode1 {
            let polished = polisher.polish(sentence, mode: .liveStream)
            XCTAssertTrue(polished.contains("Mode 1"), "Failed to restore Mode 1 from '\(sentence)': got '\(polished)'")
        }
        
        let corpusMode2 = [
            "現在是 茂 t 模式",
            "試試看 me 兔 的結果",
            "冒著吐兔 也測試一下",
            "貓的兔 也是一樣的",
            "這次用 ml 的 to 來分析"
        ]
        for sentence in corpusMode2 {
            let polished = polisher.polish(sentence, mode: .liveStream)
            XCTAssertTrue(polished.contains("Mode 2"), "Failed to restore Mode 2 from '\(sentence)': got '\(polished)'")
        }
    }
    
    func testSystemPromptFuzzyVariations() {
        let corpusPrompt = [
            "塞一個 sister Prom 進去",
            "調整 sister Pat 的內容",
            "修改 set Pro 的規則",
            "檢查 stone Prom 是否正確",
            "還有 season from 的部分",
            "修正 season Pro 的設定",
            "開頭的 To Pro 也看一下",
            "自動修復 System Promptpt 的尾音",
            "自動修復 System Promptm 的尾綴"
        ]
        for sentence in corpusPrompt {
            let polished = polisher.polish(sentence, mode: .liveStream)
            XCTAssertTrue(polished.contains("System Prompt"), "Failed to restore System Prompt from '\(sentence)': got '\(polished)'")
        }
    }
    
    func testContextualTermsRestoration() {
        let input1 = "他看到上下文這個字，所以知道要翻成 contact。"
        let output1 = polisher.polish(input1, mode: .liveStream)
        XCTAssertTrue(output1.contains("Context"), "Contextual contact should normalize to Context: \(output1)")
        
        let input2 = "請更新 Varun 文件，以及 A DM D R 的規範，還有整個 Source Coded 的架構。"
        let output2 = polisher.polish(input2, mode: .liveStream)
        XCTAssertTrue(output2.contains("README"), "Varun should normalize to README: \(output2)")
        XCTAssertTrue(output2.contains("AGENTS.md"), "A DM D R should normalize to AGENTS.md: \(output2)")
        XCTAssertTrue(output2.contains("Source Code"), "Source Coded should normalize to Source Code: \(output2)")
    }
    
    // MARK: - 3. Mode 1 Faithful Streaming vs Mode 2 Deep Polish
    
    func testMode1PreservesNaturalRepetitionsAndPunctuation() {
        let input = "好，我們測試一下。測試測試看起來好像沒有什麼問題喔，那標點符號怎麼都不見了？標點符號變少了，為什麼？"
        let output = polisher.polish(input, mode: .liveStream)
        
        // Mode 1 must preserve consecutive natural words
        XCTAssertTrue(output.contains("測試測試"), "Mode 1 must preserve consecutive repeated words: \(output)")
        // Mode 1 must preserve punctuation
        XCTAssertTrue(output.contains("，"), "Mode 1 must preserve commas: \(output)")
        XCTAssertTrue(output.contains("。"), "Mode 1 must preserve periods: \(output)")
        XCTAssertTrue(output.contains("？"), "Mode 1 must preserve question marks: \(output)")
    }
    
    func testMode2AnnihilatesStuttersAndRestarts() {
        let input = "好我們來，好我們來測，好，我們來測試一下就是有沒有問題。"
        let output = polisher.polish(input, mode: .structuredNote)
        
        XCTAssertFalse(output.contains("好我們來，好我們來測"), "Mode 2 must eliminate progressive restart loops: \(output)")
        XCTAssertTrue(output.contains("我們來測試一下"), "Mode 2 must keep the final intended sentence: \(output)")
    }
    
    func testMode2MarkdownBulletStructuring() {
        let input = "我們今天有兩個重要決策，第一點是採用本機 Apple Silicon NPU 模型，第二點是支援 OpenCC 繁體中文轉換。"
        let output = polisher.polish(input, mode: .structuredNote)
        
        XCTAssertTrue(output.contains("- 第一點"), "Mode 2 must extract bullet points with markdown: \(output)")
        XCTAssertTrue(output.contains("- 第二點"), "Mode 2 must extract bullet points with markdown: \(output)")
    }
    
    func testMode2SentenceDeduplication() {
        let input = "有可能是我的麥克風剛剛出問題。有可能是我的麥克風剛剛出問題。有可能是我的麥克風剛剛出問題。"
        let output = polisher.polish(input, mode: .structuredNote)
        
        let count = output.components(separatedBy: "有可能是我的麥克風剛剛出問題").count - 1
        XCTAssertEqual(count, 1, "Mode 2 must deduplicate identical repeated sentences across monologue: \(output)")
    }
    
    // MARK: - 4. Semantic Intent Disambiguation
    
    func testSemanticDisambiguation() {
        let input = "這段文章經過好的認識之後，羽翼變得非常清晰，把蚊子都修正好了。"
        let output = polisher.polish(input, mode: .structuredNote)
        
        XCTAssertTrue(output.contains("潤飾"), "認識 should disambiguate to 潤飾: \(output)")
        XCTAssertTrue(output.contains("語意"), "羽翼 should disambiguate to 語意: \(output)")
        XCTAssertTrue(output.contains("把文字"), "把蚊子 should disambiguate to 把文字: \(output)")
    }
}
