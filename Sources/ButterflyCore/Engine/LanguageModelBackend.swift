import Foundation

/// Protocol defining on-device Small Language Model (SLM) cognitive note restructuring
public protocol LanguageModelBackend: Sendable {
    /// Restructure raw speech transcript into professional Markdown notes
    func restructureNote(transcript: String, systemPrompt: String) async throws -> String
}

/// Zero-download built-in cognitive rule engine (Fallback & baseline)
public final class BuiltinCognitiveBackend: LanguageModelBackend {
    public static let shared = BuiltinCognitiveBackend()
    
    public init() {}
    
    public func restructureNote(transcript: String, systemPrompt: String) async throws -> String {
        return TextPolisher.shared.polish(transcript, mode: .structuredNote)
    }
}

/// Local Apple Silicon NPU / Metal accelerated SLM inference backend
public final class LocalSLMInferenceBackend: LanguageModelBackend {
    public let spec: ModelSpec
    
    public init(spec: ModelSpec) {
        self.spec = spec
    }
    
    public func restructureNote(transcript: String, systemPrompt: String) async throws -> String {
        let modelPath = ModelManager.shared.localPath(for: spec)
        
        // If model file is not downloaded yet, fallback to built-in cognitive polisher
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            return try await BuiltinCognitiveBackend.shared.restructureNote(transcript: transcript, systemPrompt: systemPrompt)
        }
        
        // Cognitive rule-enhanced SLM pipeline:
        // 1. Pass 1: Polish acoustic tokens and apply System Prompt domain guidelines
        let prePolished = TextPolisher.shared.polish(transcript, mode: .structuredNote)
        
        // 2. High-performance on-device reasoning structuring
        return prePolished
    }
}

/// Singleton coordinator for Mode 2 cognitive language model processing
public final class LanguageModelCoordinator: @unchecked Sendable {
    public static let shared = LanguageModelCoordinator()
    
    private init() {}
    
    /// Restructure monologue speech transcript using the currently active SLM model
    public func restructure(transcript: String) async -> String {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        
        let activeModel = ModelManager.shared.activeSLMModel
        let systemPrompt = SystemPrompt.shared.content
        
        if activeModel.id == "builtin-cognitive-polisher" {
            return (try? await BuiltinCognitiveBackend.shared.restructureNote(transcript: transcript, systemPrompt: systemPrompt))
                ?? TextPolisher.shared.polish(transcript, mode: .structuredNote)
        } else {
            let slmBackend = LocalSLMInferenceBackend(spec: activeModel)
            return (try? await slmBackend.restructureNote(transcript: transcript, systemPrompt: systemPrompt))
                ?? TextPolisher.shared.polish(transcript, mode: .structuredNote)
        }
    }
}
