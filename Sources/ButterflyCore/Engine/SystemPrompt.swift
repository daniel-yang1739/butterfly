import Foundation

/// System Prompt loader and manager for Butterfly AI Speech & Semantic Polishing
public final class SystemPrompt: @unchecked Sendable {
    public static let shared = SystemPrompt()
    
    /// Complete System Prompt text loaded from SYSTEM_PROMPT.md
    public private(set) var content: String
    
    public init() {
        self.content = SystemPrompt.loadFromDisk()
    }
    
    /// Load SYSTEM_PROMPT.md from file system or fallback to embedded static constant
    public static func loadFromDisk() -> String {
        let fileManager = FileManager.default
        let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        
        let candidateURLs: [URL] = [
            currentDir.appendingPathComponent("SYSTEM_PROMPT.md"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".config/butterfly/SYSTEM_PROMPT.md")
        ]
        
        for url in candidateURLs {
            if fileManager.fileExists(atPath: url.path),
               let loaded = try? String(contentsOf: url, encoding: .utf8),
               !loaded.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                return loaded
            }
        }
        
        return defaultSystemPromptText
    }
    
    /// Reload SYSTEM_PROMPT.md from disk
    public func reload() {
        self.content = SystemPrompt.loadFromDisk()
    }
    
    /// Returns the specialized System Prompt tailored for Mode 1 (Live Dictation) or Mode 2 (Smart Notes)
    public func prompt(for mode: TextPolisher.PolishMode) -> String {
        switch mode {
        case .liveStream:
            return """
            \(content)
            
            [Active Mode Directive: Mode 1 - Real-Time Live Streaming Dictation]
            - Priority: 100% Faithful Reproduction & Fluid Sentence Punctuation.
            - Do NOT summarize, reorder, or delete the speaker's ideas.
            - Accurately add natural punctuation (，, 。, ！, ？), correct typos and technical terms, and insert Pangu spacing.
            """
        case .structuredNote:
            return """
            \(content)
            
            [Active Mode Directive: Mode 2 - Smart Structured Note Synthesis]
            - Priority: Deep Semantic Comprehension, Paragraph Restructuring & Markdown Outlining.
            - Deeply understand the core message across the entire monologue.
            - Annihilate circular stutters and oral filler debris.
            - Structure distinct arguments into clean Markdown bullet points (- 第 1 點：...) and logical paragraphs.
            """
        case .conciseSummary:
            return """
            \(content)
            
            [Active Mode Directive: Concise Summary]
            - Priority: Ultra-dense key takeaways and action items.
            """
        }
    }
    
    /// Default embedded System Prompt fallback
    public static let defaultSystemPromptText: String = """
    # Butterfly AI Speech & Semantic Polishing System Prompt
    You are Butterfly, a high-precision, on-device AI speech-to-text cognitive reconstruction assistant.
    Transform spoken Chinese-English code-switching transcriptions into clean, beautifully structured notes.
    """
}
