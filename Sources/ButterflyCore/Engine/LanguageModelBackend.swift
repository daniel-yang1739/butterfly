import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public enum LanguageModelAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
}

public enum LanguageModelBackendError: LocalizedError, Sendable {
    case unavailable(String)
    case contextSizeExceeded
    case emptyResponse
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return "The language model is unavailable: \(reason)"
        case .contextSizeExceeded:
            return "The transcript exceeds the language model context window."
        case .emptyResponse:
            return "The language model returned an empty response."
        case .generationFailed(let reason):
            return "Language model generation failed: \(reason)"
        }
    }
}

public protocol LanguageModelBackend: Sendable {
    func availability() async -> LanguageModelAvailability
    func polish(
        transcript: String,
        instructions: String,
        style: SmartPolishStyle
    ) async throws -> String
}

public struct AppleFoundationModelBackend: LanguageModelBackend {
    public init() {}

    public func availability() async -> LanguageModelAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return Self.foundationModelAvailability()
        }
        #endif
        return .unavailable(reason: "Apple Foundation Models requires macOS 26 or later")
    }

    public func polish(
        transcript: String,
        instructions: String,
        style: SmartPolishStyle
    ) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await Self.generate(transcript: transcript, instructions: instructions)
        }
        #endif
        throw LanguageModelBackendError.unavailable("Apple Foundation Models requires macOS 26 or later")
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func foundationModelAvailability() -> LanguageModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(reason: String(describing: reason))
        }
    }

    @available(macOS 26.0, *)
    private static func generate(transcript: String, instructions: String) async throws -> String {
        guard case .available = foundationModelAvailability() else {
            if case .unavailable(let reason) = foundationModelAvailability() {
                throw LanguageModelBackendError.unavailable(reason)
            }
            throw LanguageModelBackendError.unavailable("Unknown availability state")
        }

        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: transcript)
            let output = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !output.isEmpty else {
                throw LanguageModelBackendError.emptyResponse
            }
            return output
        } catch let error as LanguageModelBackendError {
            throw error
        } catch {
            let description = String(describing: error)
            if description.localizedCaseInsensitiveContains("contextSizeExceeded")
                || description.localizedCaseInsensitiveContains("context size") {
                throw LanguageModelBackendError.contextSizeExceeded
            }
            throw LanguageModelBackendError.generationFailed(error.localizedDescription)
        }
    }
    #endif
}

public struct RuleBasedLanguageModelBackend: LanguageModelBackend {
    public init() {}

    public func availability() async -> LanguageModelAvailability {
        .available
    }

    public func polish(
        transcript: String,
        instructions: String,
        style: SmartPolishStyle
    ) async throws -> String {
        let mode: TextPolisher.PolishMode
        switch style {
        case .faithful:
            mode = .liveStream
        case .concise:
            mode = .concisePolish
        case .structured:
            mode = .structuredNote
        case .summary:
            mode = .conciseSummary
        }
        return TextPolisher.shared.polish(transcript, mode: mode)
    }
}
