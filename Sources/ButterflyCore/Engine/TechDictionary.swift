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
    
    /// Ensures user dictionary file exists at ~/.config/butterfly/dictionary.txt, initializing it from bundled resource if missing
    public static func ensureUserDictionaryExists() {
        let fileManager = FileManager.default
        let path = userDictionaryURL.path
        if !fileManager.fileExists(atPath: path) {
            let dir = userDictionaryURL.deletingLastPathComponent()
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            if let bundledURL = Bundle.module.url(forResource: "dictionary", withExtension: "txt"),
               let bundledContent = try? String(contentsOf: bundledURL, encoding: .utf8) {
                try? bundledContent.write(to: userDictionaryURL, atomically: true, encoding: .utf8)
            }
        }
    }
    
    /// Dynamically loads standard software engineering vocabulary from bundled repository resource (Sources/ButterflyCore/Resources/dictionary.txt)
    public static func loadBundledVocabulary() -> [String] {
        guard let url = Bundle.module.url(forResource: "dictionary", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return parseVocabulary(from: content)
    }

    /// Combined, deduplicated vocabulary loaded from repository bundled dictionary and user overrides (~/.config/butterfly/dictionary.txt)
    public static var allVocabulary: [String] {
        ensureUserDictionaryExists()
        var set = Set<String>()
        var result: [String] = []
        
        for term in loadBundledVocabulary() + loadUserVocabulary() {
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
        return vocab.prefix(30).joined(separator: ", ")
    }
}
