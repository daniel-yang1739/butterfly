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
    
    /// Combined, deduplicated vocabulary loaded strictly from user dictionary (~/.config/butterfly/dictionary.txt)
    public static var allVocabulary: [String] {
        var set = Set<String>()
        var result: [String] = []
        
        for term in loadUserVocabulary() {
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
