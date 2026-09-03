import Foundation

/// Local SLM Inference Backend for Mode 2 structured note synthesis & Mode 1 live streaming refinement
public final class LocalSLMInferenceBackend: @unchecked Sendable {
    public let spec: ModelSpec
    
    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()
    
    public init(spec: ModelSpec) {
        self.spec = spec
    }
    
    /// Format ChatML prompt template
    public func buildChatMLPrompt(transcript: String, mode: TextPolisher.PolishMode) -> String {
        let rolePrompt: String
        switch mode {
        case .liveStream:
            rolePrompt = "你是繁體中文即時語音修正助手。請將使用者的口述語音片段修復錯字並加上繁體中文標點符號。規則：直接輸出修正後的繁體中文句子，絕不重複指令、絕不輸出多餘問候。"
        case .structuredNote, .conciseSummary:
            rolePrompt = "你是專業的技術筆記秘書。請將使用者的口述語音整理為乾淨、條理分明的繁體中文 Markdown 條列筆記（每點以 - 開頭）。規則：直接輸出繁體中文筆記內容，絕不輸出問候語、絕不包含閒聊贅詞。"
        }
        
        return """
        <|im_start|>system
        \(rolePrompt)<|im_end|>
        <|im_start|>user
        \(transcript)<|im_end|>
        <|im_start|>assistant
        - 
        """
    }
    
    /// Format Llama 3 prompt template with strict anti-echo and direct prefix guidance
    public func buildLlama3Prompt(transcript: String, mode: TextPolisher.PolishMode) -> String {
        switch mode {
        case .liveStream:
            return """
            <|begin_of_text|><|start_header_id|>system<|end_header_id|>
            你是繁體中文即時語音修正助手。請將使用者的口述文字修正錯字並加上繁體中文標點符號。規則：直接輸出修正後的繁體中文句子，絕不輸出任何問候語或額外文字。<|eot_id|><|start_header_id|>user<|end_header_id|>
            \(transcript)<|eot_id|><|start_header_id|>assistant
            
            """
        case .structuredNote, .conciseSummary:
            return """
            <|begin_of_text|><|start_header_id|>system<|end_header_id|>
            你是專業的技術架構與筆記秘書。請將使用者的口述語音直接提煉整理為條理清晰的繁體中文 Markdown 條列筆記（每點以 - 開頭）。規則：直接輸出繁體中文筆記，絕不輸出問候語、絕不聊天、絕不重複使用者整段問題。<|eot_id|><|start_header_id|>user<|end_header_id|>
            \(transcript)<|eot_id|><|start_header_id|>assistant
            - 
            """
        }
    }
    
    /// Restructure monologue transcript using true local SLM inference on Metal GPU with full telemetry
    public func restructureNote(transcript: String, systemPrompt: String) async throws -> String {
        let modelPath = ModelManager.shared.localPath(for: spec)
        
        // 1. If local GGUF model weights are present on disk, execute REAL SLM neural inference
        if FileManager.default.fileExists(atPath: modelPath.path) {
            let prompt = spec.id.contains("llama")
                ? buildLlama3Prompt(transcript: transcript, mode: .structuredNote)
                : buildChatMLPrompt(transcript: transcript, mode: .structuredNote)
            
            let dispatchTimeStr = Self.timeFormatter.string(from: Date())
            let startTime = DispatchTime.now()
            
            if let output = try? await executeLocalCLI(modelPath: modelPath.path, prompt: prompt), !output.isEmpty {
                let endTime = DispatchTime.now()
                let receiveTimeStr = Self.timeFormatter.string(from: Date())
                let elapsedMs = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
                
                var cleaned = cleanSLMOutput(output)
                if !cleaned.isEmpty {
                    if !cleaned.hasPrefix("- ") && !cleaned.hasPrefix("1. ") && !cleaned.hasPrefix("#") {
                        cleaned = "- " + cleaned
                    }
                    let traditional = OpenCCTranslator.shared.convert(cleaned)
                    
                    let samplePreview = transcript.count > 50 ? String(transcript.prefix(50)) + "..." : transcript
                    print("""
                    
                    ┌─── 🧠 [Mode 2 SLM Telemetry: \(spec.displayName)] ──────────────────────────────
                    │ ⏰ Dispatched Time  : \(dispatchTimeStr)
                    │ 📥 Input Monologue   : (\(transcript.count) chars) "\(samplePreview)"
                    │ ⚡ Compute Engine    : Apple Silicon Metal GPU (Unified Memory)
                    │ ⏰ Received Time    : \(receiveTimeStr) (⏱️ Total Latency: \(String(format: "%.1f", elapsedMs)) ms)
                    │ 📤 Output Note Size  : (\(traditional.count) chars)
                    └─────────────────────────────────────────────────────────────────────────────
                    """)
                    return traditional
                }
            }
        }
        
        // 2. High-performance cognitive polishing fallback
        let polished = TextPolisher.shared.polish(transcript, mode: .structuredNote)
        return polished
    }
    
    /// Refine live streaming clause using active SLM model on Metal GPU with full telemetry
    public func refineLiveClause(clause: String) async -> String {
        let modelPath = ModelManager.shared.localPath(for: spec)
        
        if FileManager.default.fileExists(atPath: modelPath.path) {
            let prompt = spec.id.contains("llama")
                ? buildLlama3Prompt(transcript: clause, mode: .liveStream)
                : buildChatMLPrompt(transcript: clause, mode: .liveStream)
            
            let dispatchTimeStr = Self.timeFormatter.string(from: Date())
            let startTime = DispatchTime.now()
            
            if let output = try? await executeLocalCLI(modelPath: modelPath.path, prompt: prompt, maxTokens: 64), !output.isEmpty {
                let endTime = DispatchTime.now()
                let receiveTimeStr = Self.timeFormatter.string(from: Date())
                let elapsedMs = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
                
                let cleaned = cleanSLMOutput(output)
                if !cleaned.isEmpty {
                    let traditional = OpenCCTranslator.shared.convert(cleaned)
                    print("""
                    
                    ┌─── 🧠 [Mode 1 SLM Clause Telemetry: \(spec.displayName)] ────────────────────────
                    │ ⏰ Dispatched Time  : \(dispatchTimeStr)
                    │ 📥 Input Clause     : "\(clause)"
                    │ ⏰ Received Time    : \(receiveTimeStr) (⏱️ Total Latency: \(String(format: "%.1f", elapsedMs)) ms)
                    │ 📤 Refined Clause   : "\(traditional)"
                    └─────────────────────────────────────────────────────────────────────────────
                    """)
                    return traditional
                }
            }
        }
        
        return TextPolisher.shared.polish(clause, mode: .liveStream)
    }
    
    /// Execute local llama-cli runner with non-interactive --single-turn and anti-repetition flags
    internal func executeLocalCLI(modelPath: String, prompt: String, maxTokens: Int = 256) async throws -> String? {
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
                    "-n", "\(maxTokens)",
                    "-ngl", "99",
                    "--temp", "0.1",
                    "--repeat-penalty", "1.3",
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
    internal func cleanSLMOutput(_ raw: String) -> String {
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
        
        // Clean out any echo header lines or conversational hallucination prefixes
        var lines = text.components(separatedBy: .newlines)
        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("# 🦋") ||
                   trimmed.hasPrefix("<system_instructions>") ||
                   trimmed.hasPrefix("</system_instructions>") ||
                   trimmed.hasPrefix("<|begin_of_text|>") ||
                   trimmed.hasPrefix("<|start_header_id|>") ||
                   trimmed.hasPrefix("我想你可能是在問") ||
                   trimmed.hasPrefix("你可能是在問") ||
                   trimmed.hasPrefix("好的，以下是")
        }
        
        // Deduplicate consecutive duplicate lines
        var deduplicatedLines: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if deduplicatedLines.last?.trimmingCharacters(in: .whitespacesAndNewlines) != trimmed {
                deduplicatedLines.append(line)
            }
        }
        
        let result = deduplicatedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result
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
        
        let activeModel = ModelManager.shared.activeSLMModel
        let backend = LocalSLMInferenceBackend(spec: activeModel)
        return await backend.refineLiveClause(clause: transcript)
    }
}
