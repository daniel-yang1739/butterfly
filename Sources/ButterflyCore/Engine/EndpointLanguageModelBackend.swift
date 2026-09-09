import Foundation

/// Sends only transcripts and editing instructions to an explicitly configured endpoint.
public final class EndpointLanguageModelBackend: LanguageModelBackend, @unchecked Sendable {
    private let requestTemplate: URLRequest
    private let modelID: String
    private let maxTokens: Int?
    private let session: URLSession
    private let ownsSession: Bool
    private let api: PolishConfiguration.Provider.Model.API
    private let variant: PolishConfiguration.Provider.Model.Variant?
    private let reasoning: Bool?
    private let contextLimit: Int?

    public init(
        options: PolishConfiguration.Provider.Options,
        modelID: String,
        maxTokens: Int? = nil,
        api: PolishConfiguration.Provider.Model.API = .chatCompletions,
        variant: PolishConfiguration.Provider.Model.Variant? = nil,
        reasoning: Bool? = nil,
        contextLimit: Int? = nil,
        session: URLSession? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        let resolvedBaseURL = try Self.resolve(options.baseURL, environment: environment)
        guard let url = URL(string: resolvedBaseURL), let host = url.host,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)) else {
            throw LanguageModelBackendError.unavailable("baseURL must use HTTPS (HTTP is allowed for loopback servers only)")
        }
        let timeout = options.timeoutMs ?? 30_000
        guard timeout.isFinite, timeout > 0, timeout <= 300_000,
              maxTokens.map({ $0 > 0 }) ?? true else {
            throw LanguageModelBackendError.unavailable("Invalid timeoutMs or maxTokens")
        }
        if reasoning == false, variant?.reasoningEffort != nil || variant?.reasoningSummary != nil {
            throw LanguageModelBackendError.unavailable("Reasoning options conflict with reasoning: false")
        }
        if api == .chatCompletions, variant?.reasoningSummary != nil {
            throw LanguageModelBackendError.unavailable("reasoningSummary requires api: responses")
        }
        if let effort = variant?.reasoningEffort,
           !["none", "minimal", "low", "medium", "high", "xhigh"].contains(effort) {
            throw LanguageModelBackendError.unavailable("Invalid reasoningEffort")
        }
        if let verbosity = variant?.textVerbosity, !["low", "medium", "high"].contains(verbosity) {
            throw LanguageModelBackendError.unavailable("Invalid textVerbosity")
        }
        if let summary = variant?.reasoningSummary, !["auto", "concise", "detailed"].contains(summary) {
            throw LanguageModelBackendError.unavailable("Invalid reasoningSummary")
        }
        if let contextLimit, contextLimit <= 0 || (maxTokens ?? 0) >= contextLimit {
            throw LanguageModelBackendError.unavailable("Invalid context or output budget")
        }
        var request = URLRequest(url: url.appendingPathComponent(api == .responses ? "responses" : "chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout / 1000
        for (key, value) in options.headers ?? [:] {
            let resolved = try Self.resolve(value, environment: environment)
            guard !key.contains(where: { $0.isNewline }), !resolved.contains(where: { $0.isNewline }) else {
                throw LanguageModelBackendError.unavailable("Headers must not contain newlines")
            }
            request.setValue(resolved, forHTTPHeaderField: key)
        }
        if let key = options.apiKey {
            let resolved = try Self.resolve(key, environment: environment)
            guard !resolved.isEmpty, !resolved.contains(where: { $0.isNewline }) else {
                throw LanguageModelBackendError.unavailable("API key is empty or invalid")
            }
            request.setValue("Bearer \(resolved)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requestTemplate = request
        self.modelID = modelID
        self.maxTokens = maxTokens
        self.api = api
        self.variant = variant
        self.reasoning = reasoning
        self.contextLimit = contextLimit
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = timeout / 1000
        self.session = session ?? URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
        ownsSession = session == nil
    }

    deinit {
        if ownsSession { session.invalidateAndCancel() }
    }

    private static func resolve(_ value: String, environment: [String: String]) throws -> String {
        let name: String?
        if value.hasPrefix("{env:") && value.hasSuffix("}") {
            name = String(value.dropFirst(5).dropLast())
        } else if value.hasPrefix("${") && value.hasSuffix("}") {
            name = String(value.dropFirst(2).dropLast())
        } else if value.hasPrefix("$") {
            let candidate = String(value.dropFirst())
            name = candidate.allSatisfy(Self.isEnvironmentNameCharacter) && !candidate.isEmpty ? candidate : nil
        } else {
            name = nil
        }
        guard let name, !name.isEmpty, name.allSatisfy(Self.isEnvironmentNameCharacter) else {
            return value
        }
        guard let resolved = environment[name], !resolved.isEmpty else {
            throw LanguageModelBackendError.unavailable("A required endpoint environment variable is missing")
        }
        return resolved
    }

    private static func isEnvironmentNameCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "_")
    }

    public func availability() async -> LanguageModelAvailability {
        // Configuration is validated locally; no transcript or probe is sent here.
        .available
    }

    public func polish(transcript: String, instructions: String, style: SmartPolishStyle) async throws -> String {
        try Task.checkCancellation()
        // UTF-8 bytes are a conservative token estimate, not a model-specific tokenizer.
        if let contextLimit {
            let estimatedInput = transcript.utf8.count + instructions.utf8.count + 64
            guard estimatedInput < contextLimit - (maxTokens ?? 0) else {
                throw LanguageModelBackendError.contextSizeExceeded
            }
        }
        var request = requestTemplate
        var body: [String: Any] = [
            "model": modelID,
            "stream": false,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": transcript]
            ]
        ]
        if api == .responses {
            body.removeValue(forKey: "messages")
            body["input"] = transcript
            body["instructions"] = instructions
            body["store"] = false
            if let maxTokens { body["max_output_tokens"] = maxTokens }
            var options: [String: String] = [:]
            if let effort = variant?.reasoningEffort { options["effort"] = effort }
            if let summary = variant?.reasoningSummary { options["summary"] = summary }
            if !options.isEmpty { body["reasoning"] = options }
            if let verbosity = variant?.textVerbosity { body["text"] = ["verbosity": verbosity] }
        } else {
            if let maxTokens {
                body[reasoning == true || variant?.reasoningEffort != nil ? "max_completion_tokens" : "max_tokens"] = maxTokens
            }
            if let effort = variant?.reasoningEffort { body["reasoning_effort"] = effort }
            if let verbosity = variant?.textVerbosity { body["verbosity"] = verbosity }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw LanguageModelBackendError.generationFailed("Endpoint connection failed or timed out")
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw LanguageModelBackendError.generationFailed("Invalid endpoint response")
        }
        guard (200..<300).contains(response.statusCode) else {
            // Never surface raw server bodies: they may echo credentials or transcripts.
            if response.statusCode == 400,
               let error = try? JSONDecoder().decode(APIError.self, from: data),
               error.error.code == "context_length_exceeded" {
                throw LanguageModelBackendError.contextSizeExceeded
            }
            throw LanguageModelBackendError.generationFailed("Endpoint returned HTTP \(response.statusCode)")
        }
        if api == .responses {
            guard let decoded = try? JSONDecoder().decode(ResponseOutput.self, from: data),
                  decoded.status == "completed" else {
                throw LanguageModelBackendError.generationFailed("Responses output is invalid or incomplete")
            }
            let output = decoded.output.filter { $0.type == "message" && $0.role == "assistant" }
                .flatMap { $0.content ?? [] }.filter { $0.type == "output_text" }
                .compactMap(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !output.isEmpty else { throw LanguageModelBackendError.emptyResponse }
            return output
        }
        guard let decoded = try? JSONDecoder().decode(Completion.self, from: data),
              let choice = decoded.choices.first else {
            throw LanguageModelBackendError.generationFailed("Invalid Chat Completions response")
        }
        guard choice.finish_reason != "length" else {
            throw LanguageModelBackendError.generationFailed("Endpoint output was truncated; increase maxTokens")
        }
        let output = choice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !output.isEmpty else { throw LanguageModelBackendError.emptyResponse }
        return output
    }

    private struct APIError: Decodable {
        struct Detail: Decodable { let code: String? }
        let error: Detail
    }
    private struct ResponseOutput: Decodable {
        struct Item: Decodable {
            struct Content: Decodable {
                let type: String
                let text: String?
            }
            let type: String
            let role: String?
            let content: [Content]?
        }
        let status: String
        let output: [Item]
    }
    private struct Completion: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
            let finish_reason: String?
        }
        let choices: [Choice]
    }
}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
