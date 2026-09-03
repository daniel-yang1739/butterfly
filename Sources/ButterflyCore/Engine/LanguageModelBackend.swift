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
        
        // 1. If local GGUF model weights are present on disk, execute local SLM inference with timeout
        if FileManager.default.fileExists(atPath: modelPath.path) {
            let prompt = spec.id.contains("llama")
                ? buildLlama3Prompt(transcript: transcript, systemPrompt: systemPrompt)
                : buildChatMLPrompt(transcript: transcript, systemPrompt: systemPrompt)
            
            print("🧠 Mode 2: Dispatched full \(transcript.count)-char monologue into \(spec.displayName)...")
            
            let output: String? = await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    return try? await self.executeLocalCLI(modelPath: modelPath.path, prompt: prompt)
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 4_000_000_000) // 4.0s timeout
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            
            if let output = output, !output.isEmpty {
                print("✨ Mode 2: \(spec.displayName) successfully restructured into \(output.count) chars of structured notes!")
                return OpenCCTranslator.shared.convert(output)
            } else {
                print("⚡ Mode 2: Applying High-Performance Cognitive Rule Engine instantly!")
            }
        }
        
        // 2. High-performance cognitive polishing fallback
        let polished = TextPolisher.shared.polish(transcript, mode: .structuredNote)
        return polished
    }
    
    /// Execute local llama-cli runner safely without Process pipe deadlock
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
                    "-n", "512",
                    "-ngl", "99",
                    "--temp", "0.2"
                ]
                process.standardOutput = pipe
                process.standardError = Pipe()
                
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
