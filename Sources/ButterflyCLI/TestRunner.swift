import Foundation
import ButterflyCore

/// Comprehensive Zero-Dependency Unit Test Runner for Butterfly Core Engine
public enum TestRunner {
    public static func runAllTests() async {
        print("\n🧪 Running Butterfly Core Test Suite...\n" + String(repeating: "=", count: 60))
        
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

        let paragraphFirstInput = "我們已經調整選單順序，選單分成兩個區塊。第一個是啟動操作。第二個是設定與狀態。這樣可以清楚區分操作和設定。"
        let paragraphFirstOutput = polisher.polish(paragraphFirstInput, mode: .structuredNote)
        assertTrue(
            paragraphFirstOutput.components(separatedBy: "\n\n").count == 3,
            "TC-C6: Structured notes preserve paragraph-list-paragraph blocks"
        )
        assertTrue(
            paragraphFirstOutput.contains("- 啟動操作。\n- 設定與狀態。"),
            "TC-C7: Structured notes emit only complete parallel list items"
        )

        let conciseOutput = polisher.polish(paragraphFirstInput, mode: .concisePolish)
        assertTrue(!conciseOutput.contains("- "), "TC-C8: Concise polish does not force list formatting")

        let multipleListsInput = "選單分成兩區。啟動操作有兩項，第一個是 Start Voice Dictation。第二個是 Start Smart Polish。設定有兩項，第一個是 Speech Model。第二個是 Model Storage。這樣可以區分操作與設定。"
        let multipleListsOutput = polisher.polish(multipleListsInput, mode: .structuredNote)
        assertTrue(
            multipleListsOutput.contains("設定有兩項：\n\n- Speech Model。"),
            "TC-C9: Restarted numbering creates a new paragraph and list block"
        )
        
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
        _ = injector.prepareStreamingDelta(newText: "你好世界", previousText: &prev1)
        assertEqual(prev1, "你好世界", "TC-F1: Streaming forward append delta")
        
        var prev2 = "你好是界"
        _ = injector.prepareStreamingDelta(newText: "你好世界", previousText: &prev2)
        assertEqual(prev2, "你好世界", "TC-F2: Streaming in-place backspace refinement delta")
        
        var prev3 = ""
        _ = injector.prepareStreamingDelta(newText: "第一步", previousText: &prev3)
        assertEqual(prev3, "第一步", "TC-F3: Initial empty string forward typing")
        
        _ = injector.prepareStreamingDelta(newText: "第一步第二步", previousText: &prev3)
        assertEqual(prev3, "第一步第二步", "TC-F4: Multi-step incremental typing")
        
        _ = injector.prepareStreamingDelta(newText: "第一步第二步", previousText: &prev3)
        assertEqual(prev3, "第一步第二步", "TC-F5: Idempotent duplicate update (no spurious keystrokes)")

        var cursorState = String(repeating: "a", count: 30)
        let originalCursorState = cursorState
        assertEqual(injector.prepareStreamingDelta(newText: "short", previousText: &cursorState), .noChange,
                    "TC-F6: Large rejected revisions do not post deletion events")
        assertEqual(cursorState, originalCursorState, "TC-F7: Rejected revisions preserve actual cursor state")
        assertEqual(injector.prepareStreamingDelta(newText: originalCursorState + "!", previousText: &cursorState), .append(text: "!"),
                    "TC-F8: Updates after rejected revisions append only new text")
        var finalCursorState = "Hello"
        assertEqual(injector.prepareStreamingDelta(newText: "Hello world.", previousText: &finalCursorState), .append(text: " world."),
                    "TC-F9: Final transcript includes an unpublished tail")
        assertEqual(injector.prepareStreamingDelta(newText: "Hello world.", previousText: &finalCursorState), .noChange,
                    "TC-F10: Repeated final transcript does not duplicate text")
        await injector.waitForPendingInjections()

        // MARK: - 7. Sliding Transcript Reconciliation Tests
        print("\n📦 Suite 7: Sliding Transcript Reconciliation")
        let accumulator = TranscriptAccumulator()
        assertEqual(
            accumulator.appendSlidingWindow(rawText: "今天要測試語音辨識", windowStartSample: 0),
            "今天要測試語音辨識",
            "TC-G1: Initial active window"
        )
        assertEqual(
            accumulator.appendSlidingWindow(rawText: "測試語音辨識是否正常", windowStartSample: 8_000),
            "今天要測試語音辨識是否正常",
            "TC-G2: Overlapping window commits only expired prefix"
        )
        let revisionAccumulator = TranscriptAccumulator()
        _ = revisionAccumulator.appendSlidingWindow(rawText: "這是一個錯吳", windowStartSample: 0)
        assertEqual(
            revisionAccumulator.appendSlidingWindow(rawText: "這是一個錯誤", windowStartSample: 0),
            "這是一個錯誤",
            "TC-G3: Active window revision replaces provisional text"
        )

        let overlapCases: [(name: String, old: String, new: String, expected: String, start: Int)] = [
            ("Split technical name does not replay its prefix", "We need Test Container", "TestContainer supports Kafka", "We need TestContainer supports Kafka", 40000),
            ("Technical punctuation remains meaningful", "Use C++ tools.", "C tools are ready.", "Use C++ tools.C tools are ready.", 40000),
            ("Version punctuation remains meaningful", "Use version 1.25", "version 125 is ready", "Use version 1.25\u{FF0C}version 125 is ready", 40000),
            ("Technical term spacing and case", "We need Test Container, which supports Kafka.", "testcontainer which supports Kafka and Redis.", "We need testcontainer which supports Kafka and Redis.", 40000),
            ("Sentence punctuation", "We should check the service, then retry.", "check the service then retry tomorrow.", "We should check the service then retry tomorrow.", 40000),
            ("Interior words are not an overlap", "We use Kafka for events.", "Today Kafka needs monitoring.", "We use Kafka for events.Today Kafka needs monitoring.", 40000),
            ("Nonoverlapping audio preserves repetition", "Run the test.", "Run the test.", "Run the test.Run the test.", 80000),
            ("Natural repetition within one window", "Please test test the service.", "Please test test the service.", "Please test test the service.", 0),
            ("Short overlap remains supported", "We use Go", "Go now", "We use Go now", 40000),
            ("Unrelated sentences are preserved", "The input is ready.", "Another task begins.", "The input is ready.Another task begins.", 40000)
        ]
        for example in overlapCases {
            let stream = TranscriptAccumulator()
            _ = stream.appendSlidingWindow(rawText: example.old, windowStartSample: 0, windowEndSample: 80_000)
            let merged = stream.appendSlidingWindow(rawText: example.new, windowStartSample: example.start, windowEndSample: 120_000)
            assertEqual(merged, example.expected, "TC-G: " + example.name)
            var cursor = example.old
            let action = injector.prepareStreamingDelta(newText: merged, previousText: &cursor)
            var simulatedText = example.old
            switch action {
            case .append(let text): simulatedText += text
            case .replaceTail(let count, let text):
                simulatedText.removeLast(count)
                simulatedText += text
            case .noChange: break
            }
            assertEqual(cursor, simulatedText, "TC-G: Cursor state matches posted changes for " + example.name)
            assertEqual(injector.prepareStreamingDelta(newText: merged, previousText: &cursor), .noChange,
                        "TC-G: Replayed snapshot posts no duplicate for " + example.name)
        }

        // MARK: - 8. Smart Polish Orchestration Tests
        print("\n📦 Suite 8: Smart Polish Orchestration")
        let smartPrimary = CLIMockLanguageModelBackend(transform: { "Polished: \($0)" })
        let smartEngine = SmartPolishEngine(primaryBackend: smartPrimary)
        let smartResult = await smartEngine.polish("Original transcript")
        assertEqual(smartResult.text, "Polished: Original transcript", "TC-H1: Available language model polishes transcript")
        assertTrue(!smartResult.usedFallback, "TC-H2: Available language model avoids fallback")

        let unavailablePrimary = CLIMockLanguageModelBackend(
            availability: .unavailable(reason: "appleIntelligenceNotEnabled"),
            transform: { $0 }
        )
        let explicitFallback = CLIMockLanguageModelBackend(transform: { "Fallback: \($0)" })
        let fallbackEngine = SmartPolishEngine(
            primaryBackend: unavailablePrimary,
            fallbackBackend: explicitFallback
        )
        let fallbackResult = await fallbackEngine.polish("Original transcript")
        assertEqual(fallbackResult.text, "Fallback: Original transcript", "TC-H3: Unavailable Apple model uses fallback")
        assertTrue(fallbackResult.usedFallback, "TC-H4: Fallback use is reported")

        let longInput = Array(repeating: "這是一個需要保留順序的完整句子。", count: 30).joined()
        let chunkingPrimary = CLIMockLanguageModelBackend(transform: { $0 })
        let chunkingEngine = SmartPolishEngine(primaryBackend: chunkingPrimary, chunkCharacterLimit: 200)
        _ = await chunkingEngine.polish(longInput)
        let chunkRequests = await chunkingPrimary.requestCount
        assertTrue(chunkRequests > 1, "TC-H5: Long transcript is split into ordered chunks")

        assertEqual(
            GlobalHotkeyResolver.resolve(
                keyCode: 49,
                optionPressed: true,
                shiftPressed: false,
                commandPressed: false,
                controlPressed: false
            ),
            .liveDictation,
            "TC-H6: Option-Space resolves to live dictation"
        )
        assertEqual(
            GlobalHotkeyResolver.resolve(
                keyCode: 49,
                optionPressed: true,
                shiftPressed: true,
                commandPressed: false,
                controlPressed: false
            ),
            .smartPolish,
            "TC-H7: Option-Shift-Space resolves to Smart Polish"
        )

        let overflowPrimary = CLIMockLanguageModelBackend(transform: { transcript in
            if transcript.count > 80 {
                throw LanguageModelBackendError.contextSizeExceeded
            }
            return transcript
        })
        let overflowEngine = SmartPolishEngine(
            primaryBackend: overflowPrimary,
            chunkCharacterLimit: 500,
            minimumRetryChunkLength: 50
        )
        let overflowResult = await overflowEngine.polish(
            Array(repeating: "這是一段需要重新切割的內容。", count: 20).joined()
        )
        assertTrue(!overflowResult.usedFallback, "TC-H8: Context overflow recursively retries smaller chunks")
        assertTrue(await overflowPrimary.requestCount > 1, "TC-H9: Context overflow performs multiple bounded requests")

        assertEqual(
            GlobalHotkeyResolver.resolve(
                keyCode: 49,
                optionPressed: true,
                shiftPressed: true,
                commandPressed: true,
                controlPressed: false
            ),
            nil,
            "TC-H10: Command-modified shortcut is rejected"
        )

        let stylePrompts = Set(SmartPolishStyle.allCases.map {
            SmartPolishPrompt.shared.content(for: $0)
        })
        assertEqual(
            stylePrompts.count,
            SmartPolishStyle.allCases.count,
            "TC-H11: Every Smart Polish style has distinct instructions"
        )

        let structuredPrimary = CLIMockLanguageModelBackend(transform: { $0 })
        let structuredEngine = SmartPolishEngine(
            primaryBackend: structuredPrimary,
            chunkCharacterLimit: 200
        )
        _ = await structuredEngine.polish(longInput, style: .structured)
        assertTrue(
            await structuredPrimary.requestCount > 2,
            "TC-H12: Long structured text receives preparation and final passes"
        )
        
        // MARK: - Endpoint Integration (runs without XCTest)
        do {
            let configuration = try JSONDecoder().decode(PolishConfiguration.self, from: Data("""
            {"polish":{"model":"test/team/model"},"provider":{"test":{
              "type":"openai-compatible","options":{"baseURL":"https://example.invalid/v1","apiKey":"{env:TEST_TOKEN}"},
              "models":{"team/model":{"name":"Test"}}
            }}}
            """.utf8))
            assertTrue(configuration.models.contains { $0.id == "test/team/model" }, "TC-I1: Model IDs preserve slashes")
            let options = configuration.provider["test"]!.options
            do {
                _ = try EndpointLanguageModelBackend(options: options, modelID: "test", environment: [:])
                assertTrue(false, "TC-I2: Missing environment key is rejected")
            } catch {
                assertTrue(true, "TC-I2: Missing environment key is rejected")
            }
            let sessionConfiguration = URLSessionConfiguration.ephemeral
            sessionConfiguration.protocolClasses = [CLIEndpointStub.self]
            let session = URLSession(configuration: sessionConfiguration)
            defer { session.invalidateAndCancel() }
            let reasoningModel = try JSONDecoder().decode(PolishConfiguration.Provider.Model.self, from: Data("""
            {"api":"responses","reasoning":true,"interleaved":true,"defaultVariant":"xhigh",
             "variants":{"xhigh":{"reasoningEffort":"xhigh","textVerbosity":"low","reasoningSummary":"auto"}},
             "limit":{"context":512000,"output":65536}}
            """.utf8))
            assertTrue(reasoningModel.reasoning == true && reasoningModel.interleaved == true, "TC-J1: Capability metadata is decoded")
            assertEqual(try reasoningModel.outputBudget(), 65536, "TC-J2: Output limit supplies the request budget")
            for modelID in ["responses", "incomplete-responses"] {
                let backend = try EndpointLanguageModelBackend(
                    options: options, modelID: modelID, maxTokens: reasoningModel.outputBudget(),
                    api: reasoningModel.api!, variant: reasoningModel.selectedVariant(),
                    reasoning: reasoningModel.reasoning, contextLimit: reasoningModel.limit?.context,
                    session: session, environment: ["TEST_TOKEN": "test-only"]
                )
                let result = await SmartPolishEngine(primaryBackend: backend).polish("Original text", style: .faithful)
                if modelID == "responses" {
                    assertEqual(result.text, "Edited response", "TC-J3: Responses parameters map correctly and summary is excluded")
                    assertTrue(!result.usedFallback, "TC-J4: Completed Responses output is accepted")
                } else {
                    assertTrue(result.usedFallback, "TC-J5: Incomplete Responses output falls back")
                }
            }
            do {
                _ = try EndpointLanguageModelBackend(
                    options: options, modelID: "invalid", variant: reasoningModel.selectedVariant(),
                    environment: ["TEST_TOKEN": "test-only"]
                )
                assertTrue(false, "TC-J6: Chat Completions rejects reasoningSummary")
            } catch { assertTrue(true, "TC-J6: Chat Completions rejects reasoningSummary") }
            for json in [
                "{\"defaultVariant\":\"missing\"}",
                "{\"limit\":{\"context\":100,\"output\":100}}",
                "{\"maxTokens\":101,\"limit\":{\"output\":100}}"
            ] {
                do {
                    let invalid = try JSONDecoder().decode(PolishConfiguration.Provider.Model.self, from: Data(json.utf8))
                    _ = try invalid.selectedVariant()
                    _ = try invalid.outputBudget()
                    assertTrue(false, "TC-J7: Invalid variant or budget is rejected")
                } catch { assertTrue(true, "TC-J7: Invalid variant or budget is rejected") }
            }
            for model in ["success", "unauthorized", "empty", "truncated", "cancelled"] {
                let backend = try EndpointLanguageModelBackend(
                    options: options, modelID: model, session: session, environment: ["TEST_TOKEN": "test-only"]
                )
                let result = await SmartPolishEngine(primaryBackend: backend).polish("Original text", style: .faithful)
                if model == "success" {
                    assertEqual(result.text, "Edited text", "TC-I3: Endpoint request and response contract")
                    assertTrue(!result.usedFallback, "TC-I4: Successful endpoint skips fallback")
                } else if model == "cancelled" {
                    assertTrue(result.text.isEmpty && !result.usedFallback, "TC-I5: Cancellation does not insert fallback")
                } else {
                    assertTrue(result.usedFallback && !result.text.isEmpty, "TC-I6: \(model) uses local fallback")
                    assertTrue(!(result.fallbackReason ?? "").contains("secret"), "TC-I7: Server error details are not exposed")
                }
            }
        } catch {
            assertTrue(false, "Endpoint integration failed: \(error.localizedDescription)")
        }

        // MARK: - Final Summary
        print("\n" + String(repeating: "=", count: 60))
        print("🎯 Test Summary: \(passed) Passed, \(failed) Failed (Total: \(passed + failed) Assertions)")
        if failed == 0 {
            print("✨ ALL CORE LOGIC TESTS PASSED WITH 100% SUCCESS!\n")
        } else {
            print("⚠️ Some tests failed. Please review the output above.\n")
            exit(1)
        }
    }
}

/// In-memory HTTP fixture; these tests never connect to a real provider.
private final class CLIEndpointStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let model = body?["model"] as? String
        if request.url?.path == "/v1/responses" {
            let reasoning = body?["reasoning"] as? [String: String]
            let text = body?["text"] as? [String: String]
            guard request.httpMethod == "POST",
                  request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only",
                  body?["input"] as? String == "Original text",
                  body?["instructions"] as? String != nil,
                  body?["store"] as? Bool == false,
                  body?["max_output_tokens"] as? Int == 65536,
                  body?["messages"] == nil,
                  reasoning == ["effort": "xhigh", "summary": "auto"], text == ["verbosity": "low"] else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            let status = model == "incomplete-responses" ? "incomplete" : "completed"
            let response = """
            {"status":"\(status)","output":[
              {"type":"reasoning","summary":[{"type":"summary_text","text":"Do not insert this"}]},
              {"type":"message","role":"assistant","content":[{"type":"output_text","text":"Edited response"}]}]}
            """
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(response.utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let messages = body?["messages"] as? [[String: String]]
        guard request.url?.path == "/v1/chat/completions", request.httpMethod == "POST",
              request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only",
              body?["stream"] as? Bool == false,
              messages?.first?["role"] == "system", messages?.last?["content"] == "Original text" else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        if model == "cancelled" {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        let status = model == "unauthorized" ? 401 : 200
        let content = model == "empty" ? "" : "Edited text"
        let finish = model == "truncated" ? "length" : "stop"
        let response = status == 401 ? "secret" : """
        {"choices":[{"message":{"content":"\(content)"},"finish_reason":"\(finish)"}]}
        """
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor CLIMockLanguageModelBackend: LanguageModelBackend {
    private let configuredAvailability: LanguageModelAvailability
    private let transform: @Sendable (String) throws -> String
    private(set) var requestCount = 0

    init(
        availability: LanguageModelAvailability = .available,
        transform: @escaping @Sendable (String) throws -> String
    ) {
        self.configuredAvailability = availability
        self.transform = transform
    }

    func availability() async -> LanguageModelAvailability {
        configuredAvailability
    }

    func polish(
        transcript: String,
        instructions: String,
        style: SmartPolishStyle
    ) async throws -> String {
        requestCount += 1
        return try transform(transcript)
    }
}
