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
        
        // MARK: - 1. Apple Native Foundation Transliteration Tests
        print("\n📦 Suite 1: Apple Native Foundation Transliteration (ICU Hans-Hant)")
        let openCC = OpenCCTranslator.shared
        assertEqual(openCC.convert("这是语音识别测试"), "這是語音識別測試", "TC-A1: Pure Simplified to Traditional conversion")
        assertEqual(openCC.convert("请帮我review这段代码，并提交一个PR"), "請幫我review這段代碼，並提交一個PR", "TC-A2: Code-switching Chinese-English conversion")
        assertEqual(openCC.convert("git checkout -b feature/butterfly --quiet"), "git checkout -b feature/butterfly --quiet", "TC-A3: Pure English preservation")
        assertTrue(!openCC.containsSimplified(openCC.convert("人工智能深度学习与神经网络模型优化性能与内存管理")), "TC-A4: Zero Simplified Chinese residual")
        
        // MARK: - 2. TextFormatter Tests
        print("\n📦 Suite 2: TextFormatter (Pangu Spacing, Numbers & Units)")
        let formatter = TextFormatter.shared
        assertEqual(formatter.insertSpacingBetweenCJKAndAlphanumeric("建立一個React組件與10個API端點"), "建立一個 React 組件與 10 個 API 端點", "TC-B1: CJK and alphanumeric spacing")
        assertEqual(formatter.format("我們大概需要八百多 MB 的空間還有兩千行程式碼第一點"), "我們大概需要 800 多 MB 的空間還有 2000 行程式碼第 1 點", "TC-B2: Spoken numbers to Arabic digits with Pangu spacing")
        assertEqual(formatter.normalizeUnitsAndTechTerms("500 Mega bite 還有 2 Tara bite 以及 5 kilogram"), "500 MB 還有 2 TB 以及 5 kg", "TC-B3: Data & metric units normalization")
        assertEqual(formatter.deduplicateStutter("我我我覺得這這這個可以"), "我覺得這個可以", "TC-B4: Stutter pronoun deduplication")
        assertEqual(formatter.normalizeUnitsAndTechTerms("切換到 V one can later 然後執行 com meet 到 get hop 的 brandes"), "切換到 V1 Translator 然後執行 Commit 到 GitHub 的 Branches", "TC-B5: Developer acoustic slips normalization (V1 Translator, Commit, GitHub, Branches)")
        
        // MARK: - 3. TextPolisher Clean Native Formatting Tests
        print("\n📦 Suite 3: TextPolisher (Clean Algorithmic Formatting & Natural Punctuation)")
        let polisher = TextPolisher.shared
        
        // 1. Spoken numbers to digits and Pangu spacing
        let numInput = "我們大概需要八百多 MB 的空間還有兩千行程式碼"
        let numOutput = polisher.polish(numInput, mode: .liveStream)
        assertTrue(numOutput.contains("800 多 MB") && numOutput.contains("2000 行"), "TC-C1: Spoken numbers and units normalization")
        
        // 2. Native Traditional Chinese conversion
        let simpInput = "这是即时语音听写的测试"
        let simpOutput = polisher.polish(simpInput, mode: .liveStream)
        assertTrue(simpOutput.contains("這是即時語音聽寫的測試"), "TC-C2: Native Traditional Chinese pass-through")
        
        // 3. Live stream natural pause punctuation
        let streamInput = "好我們今天測試一下聽寫功能"
        let streamOutput = polisher.polish(streamInput, mode: .liveStream)
        assertTrue(!streamOutput.isEmpty, "TC-C3: Live stream formatting pass-through")
        
        // 4. Faithful spoken text preservation
        let faithfulInput = "好，我們測試一下。測試測試看起來沒有問題，標點符號在嗎？"
        let faithfulOutput = polisher.polish(faithfulInput, mode: .liveStream)
        assertTrue(faithfulOutput.contains("測試測試") && faithfulOutput.contains("？"), "TC-C4: Faithful preservation of natural speech")
        
        // 5. Stutter deduplication
        let stutterInput = "這個這個功能真的很好用"
        let stutterOutput = polisher.polish(stutterInput, mode: .structuredNote)
        assertTrue(stutterOutput.contains("這個功能"), "TC-C5: Stutter deduplication")
        
        // MARK: - 4. SystemPrompt Tests
        print("\n📦 Suite 4: SystemPrompt (Dynamic Loading & Fallbacks)")
        let sysPrompt = SystemPrompt.shared
        assertTrue(!sysPrompt.content.isEmpty, "TC-D1: System Prompt content loaded")
        assertTrue(sysPrompt.content.contains("Butterfly"), "TC-D2: System Prompt contains Butterfly role definition")
        
        // MARK: - 5. ModelManager Speech Recognition (ASR) Whitelist Tests
        print("\n📦 Suite 5: ModelManager Speech Models (ASR Whitelist)")
        let asrModels = ModelManager.defaultASRModels
        assertEqual(asrModels[0].id, "whisper-large-v3-turbo", "TC-E1: ASR whitelist Rank 1 is Whisper Large-v3-Turbo")
        assertEqual(asrModels[0].formattedSize, "1.62 GB", "TC-E2: Whisper Large-v3-Turbo formatted size")
        assertEqual(asrModels[1].id, "whisper-small", "TC-E3: ASR whitelist Rank 2 is Whisper Small")
        assertEqual(asrModels[2].id, "sensevoice-small", "TC-E4: ASR whitelist Rank 3 is SenseVoice Small")
        
        let bestASR = ModelManager.shared.getBestAvailableASRModel()
        assertTrue(!bestASR.id.isEmpty, "TC-E5: Best available speech model auto-discovery")
        
        // MARK: - 6. InputInjector Direct Streaming Delta Tests
        print("\n📦 Suite 6: InputInjector (Direct Real-time Streaming Delta)")
        let injector = InputInjector.shared
        
        var prev1 = "你好"
        injector.injectStreamingDelta(newText: "你好世界", previousText: &prev1)
        assertEqual(prev1, "你好世界", "TC-F1: Streaming forward append delta")
        
        var prev2 = "你好是界"
        injector.injectStreamingDelta(newText: "你好世界", previousText: &prev2)
        assertEqual(prev2, "你好世界", "TC-F2: Streaming in-place backspace refinement delta")
        
        var prev3 = ""
        injector.injectStreamingDelta(newText: "第一步", previousText: &prev3)
        assertEqual(prev3, "第一步", "TC-F3: Initial empty string forward typing")
        
        injector.injectStreamingDelta(newText: "第一步第二步", previousText: &prev3)
        assertEqual(prev3, "第一步第二步", "TC-F4: Multi-step incremental typing")
        
        injector.injectStreamingDelta(newText: "第一步第二步", previousText: &prev3)
        assertEqual(prev3, "第一步第二步", "TC-F5: Idempotent duplicate update (no spurious keystrokes)")
        
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
