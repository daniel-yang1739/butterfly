import XCTest
@testable import ButterflyCore

final class EndpointLanguageModelTests: XCTestCase {
    private func configuration(_ options: String = "", model: String = "gateway/team/model") throws -> PolishConfiguration {
        try JSONDecoder().decode(PolishConfiguration.self, from: Data("""
        {"polish":{"model":"\(model)"},"provider":{"gateway":{
          "type":"openai-compatible","options":{"baseURL":"https://example.com/v1"\(options)},
          "models":{"team/model":{"name":"Test Model","maxTokens":1000}}
        }}}
        """.utf8))
    }

    func testDefaultsAndModelIDsContainingSlashes() throws {
        let defaults = try JSONDecoder().decode(PolishConfiguration.self, from: Data("{}".utf8))
        XCTAssertEqual(defaults.polish.model, "local/foundation")
        let config = try configuration()
        XCTAssertTrue(config.models.contains { $0.id == "gateway/team/model" })
        XCTAssertNoThrow(try config.makeEngine())
        XCTAssertThrowsError(try config.makeEngine(model: "gateway/missing"))
    }

    func testInvalidConfigAndMissingEnvironmentAreRejected() throws {
        let config = try configuration(",\"apiKey\":\"{env:MISSING_TEST_KEY}\"")
        XCTAssertThrowsError(try EndpointLanguageModelBackend(
            options: XCTUnwrap(config.provider["gateway"]).options,
            modelID: "team/model", environment: [:]
        ))
        let invalid = try configuration(",\"timeoutMs\":0")
        XCTAssertThrowsError(try invalid.makeEngine())
    }

    func testRequestAndResponseContract() async throws {
        let config = try configuration(",\"apiKey\":\"{env:TEST_KEY}\",\"headers\":{\"X-Test\":\"yes\"}")
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [CompletionStub.self]
        let backend = try EndpointLanguageModelBackend(
            options: XCTUnwrap(config.provider["gateway"]).options,
            modelID: "team/model", maxTokens: 1000,
            session: URLSession(configuration: sessionConfig), environment: ["TEST_KEY": "test-token"]
        )
        let result = try await backend.polish(transcript: "input", instructions: "Edit faithfully", style: .faithful)
        XCTAssertEqual(result, "Edited text")
    }

    func testHTTPFailureFallsBackWithoutLeakingServerBody() async throws {
        let backend = try stubBackend(model: "failure")
        let result = await SmartPolishEngine(primaryBackend: backend).polish("Original text")
        XCTAssertTrue(result.usedFallback)
        XCTAssertTrue(result.fallbackReason?.contains("HTTP 401") == true)
        XCTAssertFalse(result.fallbackReason?.contains("secret") == true)
        XCTAssertFalse(result.text.isEmpty)
    }

    func testEmptyAndTruncatedResponsesAreRejected() async throws {
        for model in ["empty", "truncated"] {
            let backend = try stubBackend(model: model)
            do {
                _ = try await backend.polish(transcript: "input", instructions: "Edit", style: .concise)
                XCTFail("Invalid output should be rejected")
            } catch { XCTAssertTrue(error is LanguageModelBackendError) }
        }
    }

    func testCancellationDoesNotProduceFallbackText() async throws {
        let engine = SmartPolishEngine(primaryBackend: CancelledBackend())
        let result = await engine.polish("Original text")
        XCTAssertEqual(result.text, "")
        XCTAssertFalse(result.usedFallback)
    }

    private func stubBackend(model: String) throws -> EndpointLanguageModelBackend {
        let config = try configuration()
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [CompletionStub.self]
        return try EndpointLanguageModelBackend(
            options: XCTUnwrap(config.provider["gateway"]).options, modelID: model,
            session: URLSession(configuration: sessionConfig)
        )
    }
}

private struct CancelledBackend: LanguageModelBackend {
    func availability() async -> LanguageModelAvailability { .available }
    func polish(transcript: String, instructions: String, style: SmartPolishStyle) async throws -> String {
        throw CancellationError()
    }
}

private final class CompletionStub: URLProtocol {
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
        var status = 200
        var response = "{\"choices\":[{\"message\":{\"content\":\" Edited text \"},\"finish_reason\":\"stop\"}]}"
        switch model {
        case "failure": status = 401; response = "secret server details"
        case "empty": response = "{\"choices\":[{\"message\":{\"content\":\" \"}}]}"
        case "truncated": response = "{\"choices\":[{\"message\":{\"content\":\"Partial\"},\"finish_reason\":\"length\"}]}"
        default:
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test"), "yes")
            XCTAssertEqual(body?["max_tokens"] as? Int, 1000)
            XCTAssertEqual(body?["stream"] as? Bool, false)
            let messages = body?["messages"] as? [[String: String]]
            XCTAssertEqual(messages?.first, ["role": "system", "content": "Edit faithfully"])
            XCTAssertEqual(messages?.last, ["role": "user", "content": "input"])
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
