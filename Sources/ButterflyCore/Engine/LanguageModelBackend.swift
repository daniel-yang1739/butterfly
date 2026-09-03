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
        
        // 1. If local GGUF model weights are present on disk, execute local inference
        if FileManager.default.fileExists(atPath: modelPath.path) {
            let prompt = buildChatMLPrompt(transcript: transcript, systemPrompt: systemPrompt)
            if let output = try? await executeLocalCLI(modelPath: modelPath.path, prompt: prompt), !output.isEmpty {
                return OpenCCTranslator.shared.convert(output)
            }
        }
        
        // 2. High-performance cognitive polishing fallback
        let polished = TextPolisher.shared.polish(transcript, mode: .structuredNote)
        return polished
    }
    
    /// Execute local llama-cli runner if available
    private func executeLocalCLI(modelPath: String, prompt: String) async throws -> String? {
        let process = Process()
        let pipe = Pipe()
        
        // Check for llama-cli in common local paths
        let candidateCLIs = ["/usr/local/bin/llama-cli", "/opt/homebrew/bin/llama-cli"]
        guard let cliPath = candidateCLIs.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return nil
        }
        
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["-m", modelPath, "-p", prompt, "-n", "512", "-ngl", "99", "--temp", "0.2", "--no-display-prompt"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                return output
            }
        } catch {
            return nil
        }
        return nil
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
        let systemPrompt = SystemPrompt.shared.prompt(for: .structuredNote)
        let slmBackend = LocalSLMInferenceBackend(spec: activeModel)
        
        return (try? await slmBackend.restructureNote(transcript: transcript, systemPrompt: systemPrompt))
            ?? TextPolisher.shared.polish(transcript, mode: .structuredNote)
    }
    
    /// Refine live streaming clause using active SLM model & SYSTEM_PROMPT.md
    public func refineLiveStream(transcript: String) async -> String {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        
        let activeModel = ModelManager.shared.activeSLMModel
        let systemPrompt = SystemPrompt.shared.prompt(for: .liveStream)
        let slmBackend = LocalSLMInferenceBackend(spec: activeModel)
        
        let polished = (try? await slmBackend.restructureNote(transcript: transcript, systemPrompt: systemPrompt))
            ?? TextPolisher.shared.polish(transcript, mode: .liveStream)
        
        return TextPolisher.shared.polish(polished, mode: .liveStream)
    }
}
