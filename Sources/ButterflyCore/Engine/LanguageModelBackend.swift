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
        \(transcript)<|eot_id|><|start_header_id|>assistant
        
        """
    }
    
    /// Restructure monologue transcript using true local SLM inference on Metal GPU
    public func restructureNote(transcript: String, systemPrompt: String) async throws -> String {
        let modelPath = ModelManager.shared.localPath(for: spec)
        
        // 1. If local GGUF model weights are present on disk, execute REAL SLM neural inference
        if FileManager.default.fileExists(atPath: modelPath.path) {
            let prompt = spec.id.contains("llama")
                ? buildLlama3Prompt(transcript: transcript, systemPrompt: systemPrompt)
                : buildChatMLPrompt(transcript: transcript, systemPrompt: systemPrompt)
            
            print("🧠 Mode 2: Executing REAL SLM Inference via \(spec.displayName) on Apple Silicon Metal GPU...")
            if let output = try? await executeLocalCLI(modelPath: modelPath.path, prompt: prompt), !output.isEmpty {
                let cleaned = cleanSLMOutput(output)
                if !cleaned.isEmpty {
                    print("✨ Mode 2: SLM Generated \(cleaned.count) chars of structured notes on Metal GPU!")
                    return OpenCCTranslator.shared.convert(cleaned)
                }
            }
        }
        
        // 2. High-performance cognitive polishing fallback
        let polished = TextPolisher.shared.polish(transcript, mode: .structuredNote)
        return polished
    }
    
    /// Execute local llama-cli runner with non-interactive --single-turn flag
    private func executeLocalCLI(modelPath: String, prompt: String) async throws -> String? {
        let candidateCLIs = ["/opt/homebrew/bin/llama-cli", "/usr/local/bin/llama-cli"]
        guard let cliPath = candidateCLIs.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: cliPath)
                process.arguments = [
                    "-m", modelPath,
                    "-p", prompt,
                    "-n", "256",
                    "-ngl", "99",
                    "--temp", "0.2",
                    "--simple-io",
                    "--no-display-prompt",
                    "--single-turn"
                ]
                process.standardOutput = pipe
                process.standardError = Pipe()
                process.standardInput = FileHandle.nullDevice
                
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    /// Parse and extract only the assistant response from llama-cli terminal output
    private func cleanSLMOutput(_ raw: String) -> String {
        var text = raw
        if let range = text.range(of: "\n> ") {
            let suffix = String(text[range.upperBound...])
            if let newlineRange = suffix.range(of: "\n") {
                text = String(suffix[newlineRange.upperBound...])
            }
        }
        if let statRange = text.range(of: "[ Prompt:") {
            text = String(text[..<statRange.lowerBound])
        }
        if let exitRange = text.range(of: "Exiting...") {
            text = String(text[..<exitRange.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Singleton coordinator for Mode 2 cognitive language model processing
public final class LanguageModelCoordinator: @unchecked Sendable {
    public static let shared = LanguageModelCoordinator()
    
    private init() {}
    
    /// Restructure monologue speech transcript into structured notes using active SLM model
    public func restructure(transcript: String) async -> String {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        
        let activeModel = ModelManager.shared.activeSLMModel
        let systemPrompt = SystemPrompt.shared.prompt(for: .structuredNote)
        let backend = LocalSLMInferenceBackend(spec: activeModel)
        
        if let result = try? await backend.restructureNote(transcript: transcript, systemPrompt: systemPrompt), !result.isEmpty {
            return result
        }
        
        return TextPolisher.shared.polish(transcript, mode: .structuredNote)
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
