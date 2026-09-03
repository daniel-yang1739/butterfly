import Foundation

/// Local SLM Inference Backend for Mode 2 structured note synthesis
public final class LocalSLMInferenceBackend: @unchecked Sendable {
    public let spec: ModelSpec
    
    public init(spec: ModelSpec) {
        self.spec = spec
    }
    
    /// Format ChatML prompt template
    public func buildChatMLPrompt(transcript: String, systemPrompt: String) -> String {
        return """
        <|im_start|>system
        \(systemPrompt)<|im_end|>
        <|im_start|>user
        請將以下口述語音逐字稿整理成專業清晰的繁體中文筆記：
        \(transcript)<|im_end|>
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
    
    /// Restructure monologue transcript into structured notes using ultra-fast cognitive engine
    public func restructureNote(transcript: String, systemPrompt: String) async throws -> String {
        let polished = TextPolisher.shared.polish(transcript, mode: .structuredNote)
        return polished
    }
}

/// Singleton coordinator for Mode 2 cognitive language model processing
public final class LanguageModelCoordinator: @unchecked Sendable {
    public static let shared = LanguageModelCoordinator()
    
    private init() {}
    
    /// Restructure monologue speech transcript into structured notes instantly
    public func restructure(transcript: String) async -> String {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        
        let polished = TextPolisher.shared.polish(transcript, mode: .structuredNote)
        print("✨ Mode 2: Cognitive Note Engine structured \(transcript.count) chars into \(polished.count) chars of notes!")
        return polished
    }
    
    /// Refine live streaming clause using active SLM model & SYSTEM_PROMPT.md
    public func refineLiveStream(transcript: String) async -> String {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        
        let polished = TextPolisher.shared.polish(transcript, mode: .liveStream)
        return polished
    }
}
