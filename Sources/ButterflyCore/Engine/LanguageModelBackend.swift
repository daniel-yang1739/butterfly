import Foundation

/// Local SLM Inference Backend for Mode 2 structured note synthesis & Mode 1 live streaming refinement
public final class LocalSLMInferenceBackend: @unchecked Sendable {
    public let spec: ModelSpec
    
    internal static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()
    
    public init(spec: ModelSpec) {
        self.spec = spec
    }
    
    /// Get system role directive for selected mode
    public func systemRoleDirective(for mode: TextPolisher.PolishMode) -> String {
        switch mode {
        case .liveStream:
            return "你是繁體中文即時語音修正助手。請將使用者的口述文字修正錯字並加上繁體中文標點符號。規則：直接輸出修正後的繁體中文句子，絕不輸出問候語、絕不輸出系統提示詞、絕不聊天。"
        case .structuredNote, .conciseSummary:
            return "你是 Butterfly AI 專業筆記秘書。請將使用者的口述文字提煉整理成精簡、條理清晰的繁體中文 Markdown 條列筆記（以 - 開頭）。直接輸出筆記內容，絕不輸出問候語、絕不輸出系統提示詞、絕不聊天。"
        }
    }
    
    /// Restructure monologue transcript using true local SLM inference on Metal GPU with full telemetry
    public func restructureNote(transcript: String, systemPrompt: String) async throws -> String {
        // Pre-clean with homophone self-healing
        let precleaned = TextPolisher.shared.polish(transcript, mode: .liveStream)
        let modelPath = ModelManager.shared.localPath(for: spec)
        
        // 1. If local GGUF model weights are present on disk, execute REAL SLM neural inference
        if FileManager.default.fileExists(atPath: modelPath.path) {
            let sysDirective = systemRoleDirective(for: .structuredNote)
            
            let dispatchTimeStr = Self.timeFormatter.string(from: Date())
            let startTime = DispatchTime.now()
            
            if let output = try? await executeLocalCLI(modelPath: modelPath.path, sysPrompt: sysDirective, userTranscript: precleaned), !output.isEmpty {
                let endTime = DispatchTime.now()
                let receiveTimeStr = Self.timeFormatter.string(from: Date())
                let elapsedMs = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
                
                var cleaned = cleanSLMOutput(output, userTranscript: precleaned)
                if isHighQualityNote(cleaned) {
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
    
    private func isHighQualityNote(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let forbidden = [
            "使用者口述", "Butterfly AI", "專業筆記秘書", "使用者的描述",
            "角色定義", "Prompt, 他, 優先", "I can't fulfil", "cannot fulfil",
            "I am sorry", "As an AI", "I'm sorry", "I cannot", "I can't",
            "請問您需要", "好的，請問", "請隨時告知", "您需要進行", "我可以協助"
        ]
        for f in forbidden {
            if text.localizedCaseInsensitiveContains(f) { return false }
        }
        return text.contains("- ") || text.contains("1. ") || text.contains("\n")
    }
    
    /// Refine live streaming clause using active SLM model on Metal GPU with full telemetry
    public func refineLiveClause(clause: String) async -> String {
        let modelPath = ModelManager.shared.localPath(for: spec)
        
        if FileManager.default.fileExists(atPath: modelPath.path) {
            let sysDirective = systemRoleDirective(for: .liveStream)
            
            let dispatchTimeStr = Self.timeFormatter.string(from: Date())
            let startTime = DispatchTime.now()
            
            if let output = try? await executeLocalCLI(modelPath: modelPath.path, sysPrompt: sysDirective, userTranscript: clause, maxTokens: 64), !output.isEmpty {
                let endTime = DispatchTime.now()
                let receiveTimeStr = Self.timeFormatter.string(from: Date())
                let elapsedMs = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0
                
                let cleaned = cleanSLMOutput(output, userTranscript: clause)
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
    
    /// Execute local llama-cli runner with native -sys and -p arguments
    internal func executeLocalCLI(modelPath: String, sysPrompt: String, userTranscript: String, maxTokens: Int = 256) async throws -> String? {
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
                    "-sys", sysPrompt,
                    "-p", userTranscript,
                    "-n", "\(maxTokens)",
                    "-ngl", "99",
                    "--temp", "0.1",
                    "--repeat-penalty", "1.2",
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
    internal func cleanSLMOutput(_ raw: String, userTranscript: String) -> String {
        var text = raw
        if let statRange = text.range(of: "[ Prompt:") {
            text = String(text[..<statRange.lowerBound])
        }
        if let exitRange = text.range(of: "Exiting...") {
            text = String(text[..<exitRange.lowerBound])
        }
        
        // Strip the prompt echo
        if let promptRange = text.range(of: userTranscript) {
            text = String(text[promptRange.upperBound...])
        } else if let range = text.range(of: "\n> ") {
            let suffix = String(text[range.upperBound...])
            if let newlineRange = suffix.range(of: "\n") {
                text = String(suffix[newlineRange.upperBound...])
            }
        }
        
        // Clean out any banner or leftover artifacts
        var lines = text.components(separatedBy: .newlines)
        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ||
                   trimmed.hasPrefix("# 🦋") ||
                   trimmed.hasPrefix("<system_instructions>") ||
                   trimmed.hasPrefix("</system_instructions>") ||
                   trimmed.hasPrefix("<|") ||
                   trimmed.hasPrefix("using custom system prompt") ||
                   trimmed.hasPrefix("available commands:") ||
                   trimmed.hasPrefix("我想你可能是在問") ||
                   trimmed.hasPrefix("好的，以下是")
        }
        
        // Deduplicate consecutive identical lines
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
        
        let polished = TextPolisher.shared.polish(transcript, mode: .structuredNote)
        return OpenCCTranslator.shared.convert(polished)
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
