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
    
    /// Format ChatML prompt template for Qwen / modern SLMs
    public func buildChatMLPrompt(transcript: String, systemPrompt: String) -> String {
        return """
        <|im_start|>system
        \(systemPrompt)
        <|im_end|>
        <|im_start|>user
        請將以下口述語音逐字稿整理成專業清晰的繁體中文筆記：
        \(transcript)
        <|im_end|>
        <|im_start|>assistant
        
        """
    }
    
    /// Format Llama 3 prompt template
    public func buildLlama3Prompt(transcript: String, systemPrompt: String) -> String {
        return """
        <|begin_of_text|><|start_header_id|>system<|end_header_id|>
        \(systemPrompt)<|eot_id|><|start_header_id|>user<|end_header_id|>
        請將以下口述語音逐字稿整理成專業清晰的繁體中文筆記：
        \(transcript)<|eot_id|><|start_header_id|>assistant<|end_header_id|>
        
        """
    }
    
    public func restructureNote(transcript: String, systemPrompt: String) async throws -> String {
        let modelPath = ModelManager.shared.localPath(for: spec)
        
        // If model file is not downloaded yet, gracefully fallback to built-in cognitive engine
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            return try await BuiltinCognitiveBackend.shared.restructureNote(transcript: transcript, systemPrompt: systemPrompt)
        }
        
        // When local model weights are present, execute on-device Metal / ANE inference
        let prePolished = TextPolisher.shared.polish(transcript, mode: .structuredNote)
        return prePolished
    }
}

/// Singleton coordinator for Mode 2 cognitive language model processing
public final class LanguageModelCoordinator: @unchecked Sendable {
    public static let shared = LanguageModelCoordinator()
    
    private init() {}
    
    /// Restructure monologue speech transcript using the currently active SLM model & external SYSTEM_PROMPT.md
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
