import Foundation
import ButterflyCore

/// Comprehensive Zero-Dependency Unit Test Runner for Butterfly Core Engine
public enum TestRunner {
    public static func runAllTests() {
        print("\n🧪 Running Butterfly Core Test Suite (26 Core Logic Assertions)...\n" + String(repeating: "=", count: 60))
        
        var passed = 0
        var failed = 0
        
        func assertTrue(_ condition: Bool, _ message: String) {
            if condition {
                passed += 1
                print("  ✅ [PASS] \(message)")
            } else {
                failed += 1
                print("  ❌ [FAIL] \(message)")
            }
        }
        
        func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
            if actual == expected {
                passed += 1
                print("  ✅ [PASS] \(message)")
            } else {
                failed += 1
                print("  ❌ [FAIL] \(message) -> Expected '\(expected)', got '\(actual)'")
            }
        }
        
        // MARK: - 1. OpenCCTranslator Tests
        print("\n📦 Suite 1: OpenCCTranslator (s2twp Taiwan Standard)")
        let openCC = OpenCCTranslator.shared
        assertEqual(openCC.convert("这是语音识别测试"), "這是語音識別測試", "TC-A1: Pure Simplified to Traditional conversion")
        assertEqual(openCC.convert("服务器内存不足，请更新数据库与界面代码，使用默认设置"), "伺服器記憶體不足，請更新資料庫與介面程式碼，使用預設設定", "TC-A2: Taiwan vocabulary adaptation")
        assertEqual(openCC.convert("请帮我review这段React代码，并提交一个PR"), "請幫我review這段React程式碼，並提交一個PR", "TC-A3: Code-switching Chinese-English conversion")
        assertEqual(openCC.convert("git checkout -b feature/butterfly --quiet"), "git checkout -b feature/butterfly --quiet", "TC-A4: Pure English preservation")
        assertTrue(!openCC.containsSimplified(openCC.convert("人工智能深度学习与神经网络模型优化性能与内存管理")), "TC-A5: Zero Simplified Chinese residual")
        
        // MARK: - 2. TextFormatter Tests
        print("\n📦 Suite 2: TextFormatter (Pangu Spacing, Numbers & Units)")
        let formatter = TextFormatter.shared
        assertEqual(formatter.insertSpacingBetweenCJKAndAlphanumeric("建立一個React組件與10個API端點"), "建立一個 React 組件與 10 個 API 端點", "TC-B1: CJK and alphanumeric spacing")
        assertEqual(formatter.format("我們大概需要八百多 MB 的空間還有兩千行程式碼第一點"), "我們大概需要 800 多 MB 的空間還有 2000 行程式碼第 1 點", "TC-B2: Spoken numbers to Arabic digits with Pangu spacing")
        assertEqual(formatter.normalizeUnitsAndTechTerms("500 Mega bite 還有 2 Tara bite 以及 5 kilogram"), "500 MB 還有 2 TB 以及 5 kg", "TC-B3: Data & metric units normalization")
        assertEqual(formatter.deduplicateStutter("我我我覺得這這這個可以"), "我覺得這個可以", "TC-B4: Stutter pronoun deduplication")
        
        // MARK: - 3. TextPolisher Two-Pass Cognitive Engine Tests
        print("\n📦 Suite 3: TextPolisher (Two-Pass Cognitive Intent Reconstruction)")
        let polisher = TextPolisher.shared
        
        // Mode 1 & 2 boundary-free fuzzy restoration
        let mode1Input = "切換到 沒ode 1 試試看 茂 the one 模式"
        let mode1Output = polisher.polish(mode1Input, mode: .liveStream)
        assertTrue(mode1Output.contains("Mode 1"), "TC-C1: Mode 1 fuzzy phonetic restoration ('沒ode 1' -> 'Mode 1')")
        
        let mode2Input = "試試看 茂 t 與 冒著吐兔 以及 貓的兔 的結果"
        let mode2Output = polisher.polish(mode2Input, mode: .liveStream)
        assertTrue(mode2Output.contains("Mode 2"), "TC-C2: Mode 2 fuzzy phonetic restoration ('茂 t', '冒著吐兔' -> 'Mode 2')")
        
        // System Prompt fuzzy restoration & typo self-healing
        let promptInput = "設定一個 sister Prom 以及 sister from 還有 season Pro 和 To Pro，自動修復 System Promptpt"
        let promptOutput = polisher.polish(promptInput, mode: .liveStream)
        let promptCount = promptOutput.components(separatedBy: "System Prompt").count - 1
        assertTrue(promptCount >= 4, "TC-C3: System Prompt fuzzy restoration and typo self-healing")
        
        // Contextual terms
        let contextInput = "看到上下文這個字，所以知道要翻成 contact。"
        let contextOutput = polisher.polish(contextInput, mode: .liveStream)
        assertTrue(contextOutput.contains("Context"), "TC-C4: Contextual contact restoration ('翻成 contact' -> 'Context')")
        
        let docInput = "請更新 Varun 文件，以及 A DM D R 的規範，還有整個 Source Coded 的架構。"
        let docOutput = polisher.polish(docInput, mode: .liveStream)
        assertTrue(docOutput.contains("README") && docOutput.contains("AGENTS.md") && docOutput.contains("Source Code"), "TC-C5: Doc & Architecture keywords restoration ('Varun' -> 'README', 'A DM D R' -> 'AGENTS.md')")
        
        // Mode 1 Faithful preservation
        let mode1Faithful = "好，我們測試一下。測試測試看起來沒有問題，標點符號在嗎？"
        let mode1FaithfulOut = polisher.polish(mode1Faithful, mode: .liveStream)
        assertTrue(mode1FaithfulOut.contains("測試測試") && mode1FaithfulOut.contains("？"), "TC-C6: Mode 1 faithful preservation (natural repetitions and punctuation kept)")
        
        // Mode 2 Deep smart note polishing
        let mode2Stutter = "好我們來，好我們來測，好，我們來測試一下就是有沒有問題。"
        let mode2StutterOut = polisher.polish(mode2Stutter, mode: .structuredNote)
        assertTrue(!mode2StutterOut.contains("好我們來，好我們來測") && mode2StutterOut.contains("我們來測試一下"), "TC-C7: Mode 2 progressive restart annihilation")
        
        let mode2Bullet = "我們有兩個重要決策，第一點是採用本機模型，第二點是支援 OpenCC 繁中。"
        let mode2BulletOut = polisher.polish(mode2Bullet, mode: .structuredNote)
        assertTrue(mode2BulletOut.contains("- 第 1 點") && mode2BulletOut.contains("- 第 2 點"), "TC-C8: Mode 2 Markdown bullet point extraction ('- 第 1 點', '- 第 2 點')")
        
        let mode2Dedup = "有可能是麥克風出問題。有可能是麥克風出問題。有可能是麥克風出問題。"
        let mode2DedupOut = polisher.polish(mode2Dedup, mode: .structuredNote)
        let dedupCount = mode2DedupOut.components(separatedBy: "有可能是麥克風出問題").count - 1
        assertEqual(dedupCount, 1, "TC-C9: Mode 2 whole-sentence deduplication across long monologue")
        
        // Semantic intent
        let semanticInput = "這段文章經過好的認識之後，羽翼變得非常清晰，把蚊子都修正好了。"
        let semanticOutput = polisher.polish(semanticInput, mode: .structuredNote)
        assertTrue(semanticOutput.contains("潤飾") && semanticOutput.contains("語意") && semanticOutput.contains("把文字"), "TC-C10: Semantic intent disambiguation ('認識' -> '潤飾', '羽翼' -> '語意')")
        
        // MARK: - 4. SystemPrompt Tests
        print("\n📦 Suite 4: SystemPrompt (Dynamic Loading & Fallbacks)")
        let sysPrompt = SystemPrompt.shared
        assertTrue(!sysPrompt.content.isEmpty, "TC-D1: System Prompt content loaded")
        assertTrue(sysPrompt.content.contains("Butterfly"), "TC-D2: System Prompt contains Butterfly role definition")
        
        // MARK: - 5. ModelManager Dual-Track & SLM Tests
        print("\n📦 Suite 5: ModelManager Dual-Track (ASR & SLM Whitelists)")
        let asrModels = ModelManager.defaultASRModels
        assertEqual(asrModels[0].id, "whisper-large-v3-turbo", "TC-E1: ASR whitelist Rank 1 is Whisper Large-v3-Turbo")
        assertEqual(asrModels[0].formattedSize, "848.3 MB", "TC-E2: Whisper Large-v3-Turbo formatted size")
        
        let slmModels = ModelManager.defaultSLMModels
        assertEqual(slmModels[0].id, "qwen2.5-0.5b-instruct", "TC-E3: SLM whitelist Rank 1 is Qwen2.5-0.5B-Instruct")
        assertEqual(slmModels[1].id, "llama-3.2-1b-instruct", "TC-E4: SLM whitelist Rank 2 is Llama-3.2-1B-Instruct")
        
        let bestASR = ModelManager.shared.getBestAvailableASRModel()
        let bestSLM = ModelManager.shared.getBestAvailableSLMModel()
        assertTrue(!bestASR.id.isEmpty && !bestSLM.id.isEmpty, "TC-E5: Dual-track best available model auto-discovery")
        
        // MARK: - 6. InputInjector Tests
        print("\n📦 Suite 6: InputInjector (Streaming In-Place Delta)")
        let injector = InputInjector.shared
        var prev1 = "你好"
        injector.injectStreamingDelta(newText: "你好世界", previousText: &prev1)
        assertEqual(prev1, "你好世界", "TC-F1: Streaming forward append delta")
        
        var prev2 = "你好是界"
        injector.injectStreamingDelta(newText: "你好世界", previousText: &prev2)
        assertEqual(prev2, "你好世界", "TC-F2: Streaming in-place backspace refinement delta")
        
        // MARK: - 7. SlidingWindowBuffer Tests (Mode 1 Plan A Engine)
        print("\n📦 Suite 7: SlidingWindowBuffer (Cumulative Streaming & Avalanche Prevention)")
        let buffer = SlidingWindowBuffer()
        buffer.reset()
        
        // TC-G1: Streaming forward append
        let a1 = buffer.appendStreamingText("你好")
        assertEqual(a1, .append(text: "你好"), "TC-G1: Sliding window append fast path")
        let a2 = buffer.appendStreamingText("你好世界")
        assertEqual(a2, .append(text: "世界"), "TC-G2: Incremental streaming append without backspaces")
        
        // TC-G3: Silence pause-gated contextual self-healing ('上下文 contact' -> '上下文 Context')
        buffer.reset()
        _ = buffer.appendStreamingText("上下文 contact")
        let pauseAction = buffer.onPauseTriggered()
        assertEqual(pauseAction, .replaceTail(backspaces: 7, replacement: "Context"), "TC-G3: Pause-gated phonetic self-healing ('contact' -> 'Context')")
        assertEqual(buffer.injectedCumulativeText, "上下文 Context", "TC-G4: Cumulative mirror updated cleanly")
        
        // TC-G5: Avalanche Prevention Test (Continuous Cumulative ASR Updates)
        let a3 = buffer.appendStreamingText("上下文 Context，現在是不是會突然出現一些雪崩效應")
        assertEqual(a3, .append(text: "，現在是不是會突然出現一些雪崩效應"), "TC-G5: Avalanche prevention (appends only new suffix without repeating earlier text)")
        
        // TC-G6: Numbers & Units pause-gated normalization
        buffer.reset()
        _ = buffer.appendStreamingText("八百 MB")
        let pauseNumAction = buffer.onPauseTriggered()
        assertEqual(pauseNumAction, .replaceTail(backspaces: 5, replacement: "800 MB"), "TC-G6: Numbers and units pause-gated normalization ('八百 MB' -> '800 MB')")
        
        // MARK: - Final Summary
        print("\n" + String(repeating: "=", count: 60))
        print("🎯 Test Summary: \(passed) Passed, \(failed) Failed (Total: \(passed + failed) Assertions)")
        if failed == 0 {
            print("✨ ALL 34 CORE LOGIC TESTS PASSED WITH 100% SUCCESS!\n")
        } else {
            print("⚠️ Some tests failed. Please review the output above.\n")
            exit(1)
        }
    }
}
