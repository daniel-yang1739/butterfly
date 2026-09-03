import Foundation

/// Comprehensive developer and software engineering lexicon for speech recognition contextual biasing
public struct TechDictionary: Sendable {
    
    /// User custom dictionary file path: ~/.config/butterfly/dictionary.txt
    public static var userDictionaryURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/butterfly/dictionary.txt")
    }
    
    /// Dynamically loads custom vocabulary from ~/.config/butterfly/dictionary.txt
    public static func loadUserVocabulary() -> [String] {
        let url = userDictionaryURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return parseVocabulary(from: content)
    }
    
    /// Dynamically loads official open-source Rime tech & developer vocabulary from upstream dict files
    public static func loadBundledVocabulary() -> [String] {
        var results: [String] = []
        
        // 1. Official upstream Rime English & IT extensions (rime_en_ext.dict.yaml)
        if let url = Bundle.module.url(forResource: "rime_en_ext", withExtension: "dict.yaml"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            results.append(contentsOf: parseRimeDict(from: content))
        }
        
        // 2. Official upstream Rime Chinese-English mixed lexicon (rime_cn_en.txt)
        if let url = Bundle.module.url(forResource: "rime_cn_en", withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            results.append(contentsOf: parseVocabulary(from: content))
        }
        
        return results
    }
    
    /// Parse official Rime tab-separated .dict.yaml format
    private static func parseRimeDict(from content: String) -> [String] {
        var words: [String] = []
        var inHeader = false
        
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed == "---" { inHeader = true; continue }
            if trimmed == "..." { inHeader = false; continue }
            if inHeader { continue }
            
            // First column in Rime is the actual target word
            let parts = trimmed.components(separatedBy: "\t")
            if let first = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
                // Ignore html entities like &nbsp;
                if !first.hasPrefix("&") && first.count > 1 {
                    words.append(first)
                }
            }
        }
        return words
    }
    
    /// Clean and parse text content into deduplicated word tokens
    private static func parseVocabulary(from content: String) -> [String] {
        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .flatMap { line in
                line.components(separatedBy: CharacterSet(charactersIn: ",;\t"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
    }
    
    /// Combined, deduplicated vocabulary loaded from user dictionary (~/.config/butterfly/dictionary.txt) and bundled resource
    public static var allVocabulary: [String] {
        var set = Set<String>()
        var result: [String] = []
        
        for term in loadUserVocabulary() + loadBundledVocabulary() {
            if !set.contains(term) {
                set.insert(term)
                result.append(term)
            }
        }
        return result
    }
    
    /// Formatted Whisper Initial Prompt (Prime attention for code-switching & technical speech)
    public static var whisperInitialPrompt: String {
        let vocab = allVocabulary
        if vocab.isEmpty {
            return "以下是標準繁體中文（台灣）語音聽寫對話，請忠實記錄語音內容。"
        }
        let topTerms = vocab.prefix(30).joined(separator: ", ")
        return "以下是繁體中文（台灣）語音聽寫對話，包含詞彙：\(topTerms)。請忠實辨識。"
    }
}
