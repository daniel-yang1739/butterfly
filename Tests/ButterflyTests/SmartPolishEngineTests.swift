import XCTest
@testable import ButterflyCore

final class SmartPolishEngineTests: XCTestCase {
    func testUsesFoundationBackendWhenAvailable() async {
        let primary = MockLanguageModelBackend(transform: { "Polished: \($0)" })
        let engine = SmartPolishEngine(primaryBackend: primary)

        let result = await engine.polish("Original transcript")

        XCTAssertEqual(result.text, "Polished: Original transcript")
        XCTAssertFalse(result.usedFallback)
        let requests = await primary.requests
        XCTAssertEqual(requests, ["Original transcript"])
    }

    func testFallsBackWhenFoundationModelIsUnavailable() async {
        let primary = MockLanguageModelBackend(
            availability: .unavailable(reason: "appleIntelligenceNotEnabled"),
            transform: { $0 }
        )
        let fallback = MockLanguageModelBackend(transform: { "Fallback: \($0)" })
        let engine = SmartPolishEngine(primaryBackend: primary, fallbackBackend: fallback)

        let result = await engine.polish("Original transcript")

        XCTAssertEqual(result.text, "Fallback: Original transcript")
        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(result.fallbackReason, "appleIntelligenceNotEnabled")
    }

    func testLongTranscriptIsPolishedInOrderedChunks() async {
        let primary = MockLanguageModelBackend(transform: { "[\($0)]" })
        let engine = SmartPolishEngine(primaryBackend: primary, chunkCharacterLimit: 200)
        let transcript = Array(repeating: "這是一個需要保留順序的完整句子。", count: 30).joined()

        let result = await engine.polish(transcript)
        let requests = await primary.requests

        XCTAssertGreaterThan(requests.count, 1)
        XCTAssertFalse(result.usedFallback)
        XCTAssertTrue(result.text.hasPrefix("[這是一個需要保留順序的完整句子"))
    }

    func testContextOverflowRecursivelySplitsTheChunk() async {
        let primary = MockLanguageModelBackend(transform: { transcript in
            if transcript.count > 80 {
                throw LanguageModelBackendError.contextSizeExceeded
            }
            return transcript
        })
        let engine = SmartPolishEngine(
            primaryBackend: primary,
            chunkCharacterLimit: 500,
            minimumRetryChunkLength: 50
        )
        let transcript = Array(repeating: "這是一段測試內容。", count: 30).joined()

        let result = await engine.polish(transcript)
        let requests = await primary.requests

        XCTAssertFalse(result.usedFallback)
        XCTAssertGreaterThan(requests.count, 1)
    }

    func testEveryStyleAddsDistinctInstructions() {
        let prompts = SmartPolishStyle.allCases.map {
            SmartPolishPrompt.shared.content(for: $0)
        }

        XCTAssertEqual(Set(prompts).count, SmartPolishStyle.allCases.count)
        XCTAssertTrue(prompts[0].contains("faithful proofread"))
        XCTAssertTrue(prompts[1].contains("concise polish"))
        XCTAssertTrue(prompts[2].contains("structured notes"))
        XCTAssertTrue(prompts[3].contains("summary"))
    }

    func testLongStructuredTextUsesPreparationAndFinalPass() async {
        let primary = MockLanguageModelBackend(transform: { $0 })
        let engine = SmartPolishEngine(primaryBackend: primary, chunkCharacterLimit: 200)
        let transcript = Array(repeating: "這是一個需要重新組織的完整句子。", count: 30).joined()

        _ = await engine.polish(transcript, style: .structured)

        let requests = await primary.requests
        XCTAssertGreaterThan(requests.count, 2)
        XCTAssertEqual(requests.last?.replacingOccurrences(of: "\n\n", with: ""), transcript)
    }

    func testHotkeyResolverDistinguishesBothModes() {
        XCTAssertEqual(
            GlobalHotkeyResolver.resolve(
                keyCode: 49,
                optionPressed: true,
                shiftPressed: false,
                commandPressed: false,
                controlPressed: false
            ),
            .liveDictation
        )
        XCTAssertEqual(
            GlobalHotkeyResolver.resolve(
                keyCode: 49,
                optionPressed: true,
                shiftPressed: true,
                commandPressed: false,
                controlPressed: false
            ),
            .smartPolish
        )
        XCTAssertNil(
            GlobalHotkeyResolver.resolve(
                keyCode: 49,
                optionPressed: true,
                shiftPressed: true,
                commandPressed: true,
                controlPressed: false
            )
        )
    }
}

private actor MockLanguageModelBackend: LanguageModelBackend {
    private let configuredAvailability: LanguageModelAvailability
    private let transform: @Sendable (String) throws -> String
    private(set) var requests: [String] = []

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
        requests.append(transcript)
        return try transform(transcript)
    }
}
