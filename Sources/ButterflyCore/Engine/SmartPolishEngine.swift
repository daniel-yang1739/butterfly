import Foundation

public struct SmartPolishResult: Equatable, Sendable {
    public let text: String
    public let usedFallback: Bool
    public let fallbackReason: String?

    public init(text: String, usedFallback: Bool, fallbackReason: String? = nil) {
        self.text = text
        self.usedFallback = usedFallback
        self.fallbackReason = fallbackReason
    }
}

public actor SmartPolishEngine {
    public static let shared = SmartPolishEngine()

    private let primaryBackend: any LanguageModelBackend
    private let fallbackBackend: any LanguageModelBackend
    private let chunkCharacterLimit: Int
    private let minimumRetryChunkLength: Int

    public init(
        primaryBackend: any LanguageModelBackend = AppleFoundationModelBackend(),
        fallbackBackend: any LanguageModelBackend = RuleBasedLanguageModelBackend(),
        chunkCharacterLimit: Int = 1_500,
        minimumRetryChunkLength: Int = 200
    ) {
        self.primaryBackend = primaryBackend
        self.fallbackBackend = fallbackBackend
        self.chunkCharacterLimit = max(200, chunkCharacterLimit)
        self.minimumRetryChunkLength = max(50, minimumRetryChunkLength)
    }

    public func availability() async -> LanguageModelAvailability {
        await primaryBackend.availability()
    }

    public func polish(
        _ transcript: String,
        style: SmartPolishStyle = .concise
    ) async -> SmartPolishResult {
        let input = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            return SmartPolishResult(text: "", usedFallback: false)
        }

        switch await primaryBackend.availability() {
        case .available:
            do {
                let polishedChunks: [String]
                switch style {
                case .faithful, .concise:
                    polishedChunks = try await polishInIndependentChunks(input, style: style)
                case .structured, .summary:
                    polishedChunks = try await polishHolistically(input, style: style)
                }
                let output = polishedChunks
                    .map { OpenCCTranslator.shared.convert($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
                guard !output.isEmpty else {
                    throw LanguageModelBackendError.emptyResponse
                }
                return SmartPolishResult(text: output, usedFallback: false)
            } catch {
                return await fallbackResult(for: input, style: style, reason: error.localizedDescription)
            }
        case .unavailable(let reason):
            return await fallbackResult(for: input, style: style, reason: reason)
        }
    }

    private func polishInIndependentChunks(
        _ input: String,
        style: SmartPolishStyle
    ) async throws -> [String] {
        let chunks = Self.splitAtSentenceBoundaries(input, maximumCharacters: chunkCharacterLimit)
        var results: [String] = []
        for chunk in chunks {
            results.append(contentsOf: try await polishChunk(
                chunk,
                instructions: SmartPolishPrompt.shared.content(for: style),
                style: style
            ))
        }
        return results
    }

    /// Long structured documents need a preparation pass before the final global rewrite.
    private func polishHolistically(
        _ input: String,
        style: SmartPolishStyle
    ) async throws -> [String] {
        let chunks = Self.splitAtSentenceBoundaries(input, maximumCharacters: chunkCharacterLimit)
        guard chunks.count > 1 else {
            return try await polishChunk(
                input,
                instructions: SmartPolishPrompt.shared.content(for: style),
                style: style
            )
        }

        var prepared: [String] = []
        for chunk in chunks {
            prepared.append(contentsOf: try await polishChunk(
                chunk,
                instructions: SmartPolishPrompt.shared.preprocessingContent(for: style),
                style: .faithful
            ))
        }

        return try await polishChunk(
            prepared.joined(separator: "\n\n"),
            instructions: SmartPolishPrompt.shared.content(for: style),
            style: style
        )
    }

    private func polishChunk(
        _ chunk: String,
        instructions: String,
        style: SmartPolishStyle
    ) async throws -> [String] {
        do {
            return [try await primaryBackend.polish(
                transcript: chunk,
                instructions: instructions,
                style: style
            )]
        } catch LanguageModelBackendError.contextSizeExceeded {
            guard chunk.count > minimumRetryChunkLength else { throw LanguageModelBackendError.contextSizeExceeded }
            let halves = Self.splitNearMiddle(chunk)
            guard halves.count > 1 else { throw LanguageModelBackendError.contextSizeExceeded }
            var results: [String] = []
            for half in halves {
                results.append(contentsOf: try await polishChunk(
                    half,
                    instructions: instructions,
                    style: style
                ))
            }
            return results
        }
    }

    private func fallbackResult(
        for transcript: String,
        style: SmartPolishStyle,
        reason: String
    ) async -> SmartPolishResult {
        let output = (try? await fallbackBackend.polish(
            transcript: transcript,
            instructions: SmartPolishPrompt.shared.content(for: style),
            style: style
        )) ?? transcript
        return SmartPolishResult(text: output, usedFallback: true, fallbackReason: reason)
    }

    static func splitAtSentenceBoundaries(_ text: String, maximumCharacters: Int) -> [String] {
        guard text.count > maximumCharacters else { return [text] }

        let boundaryCharacters: Set<Character> = ["。", "！", "？", "!", "?", "\n"]
        var sentences: [String] = []
        var sentence = ""
        for character in text {
            sentence.append(character)
            if boundaryCharacters.contains(character) {
                if !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sentences.append(sentence)
                }
                sentence = ""
            }
        }
        if !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sentences.append(sentence)
        }
        guard sentences.count > 1 else {
            return stride(from: 0, to: text.count, by: maximumCharacters).map { offset in
                let start = text.index(text.startIndex, offsetBy: offset)
                let end = text.index(start, offsetBy: min(maximumCharacters, text.count - offset))
                return String(text[start..<end])
            }
        }

        var chunks: [String] = []
        var current = ""
        for sentence in sentences {
            let candidate = current + sentence
            if candidate.count > maximumCharacters, !current.isEmpty {
                chunks.append(current)
                current = sentence
            } else {
                current = candidate
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks.flatMap { chunk in
            chunk.count <= maximumCharacters
                ? [chunk]
                : splitAtSentenceBoundaries(chunk, maximumCharacters: maximumCharacters)
        }
    }

    private static func splitNearMiddle(_ text: String) -> [String] {
        guard text.count > 1 else { return [text] }
        let middleOffset = text.count / 2
        let characters = Array(text)
        let boundaryCharacters: Set<Character> = ["。", "！", "？", "!", "?", "，", ",", "\n"]

        var boundary: Int?
        for distance in 0..<middleOffset {
            let right = middleOffset + distance
            if right < characters.count, boundaryCharacters.contains(characters[right]) {
                boundary = right + 1
                break
            }
            let left = middleOffset - distance
            if left > 0, boundaryCharacters.contains(characters[left]) {
                boundary = left + 1
                break
            }
        }

        let splitOffset = boundary ?? middleOffset
        let first = String(characters[..<splitOffset]).trimmingCharacters(in: .whitespacesAndNewlines)
        let second = String(characters[splitOffset...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return [first, second].filter { !$0.isEmpty }
    }
}
