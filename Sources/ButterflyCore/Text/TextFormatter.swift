import Foundation

/// Text layout, CJK-alphanumeric spacing, and punctuation formatter
public final class TextFormatter {
    public static let shared = TextFormatter()
    
    public init() {}
    
    /// Full text formatting pipeline
    public func format(
        _ text: String,
        insertCJKSpacing: Bool = true,
        removeStutter: Bool = true,
        trimTrailingPunctuation: Bool = true
    ) -> String {
        guard !text.isEmpty else { return text }
        
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Remove speech stutter and repetitions
        if removeStutter {
            result = deduplicateStutter(result)
        }
        
        // 2. Insert spacing between CJK and alphanumeric characters (Pangu Spacing)
        if insertCJKSpacing {
            result = insertSpacingBetweenCJKAndAlphanumeric(result)
        }
        
        // 3. Trim trailing punctuation for short phrases
        if trimTrailingPunctuation {
            result = trimTrailingPunctuationIfNeeded(result)
        }
        
        return result
    }
    
    /// Deduplicate single Chinese character stutters (3+ repetitions or common 2-char stutter prefixes)
    public func deduplicateStutter(_ text: String) -> String {
        guard text.count >= 2 else { return text }
        var result = text
        
        // 1. Deduplicate 3 or more consecutive identical characters (e.g. "我我我" -> "我")
        let triplePattern = "([\\u4e00-\\u9fa5])\\1{2,}"
        if let regex = try? NSRegularExpression(pattern: triplePattern, options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }
        
        // 2. Remove common 2-character stutter pronouns/conjunctions at phrase starts (e.g. "我我覺得" -> "我覺得")
        let stutterPrefixPattern = "([，。！？\n\\s]|^)(我我|這這|那那|但但|就就|如如)([\\u4e00-\\u9fa5])"
        if let regex = try? NSRegularExpression(pattern: stutterPrefixPattern, options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1$2$3")
            // Take first char of duplicated pronoun
            let cleanPattern = "([，。！？\n\\s]|^)(我|這|那|但|就|如)\\2([\\u4e00-\\u9fa5])"
            if let cleanRegex = try? NSRegularExpression(pattern: cleanPattern, options: []) {
                let r = NSRange(location: 0, length: result.utf16.count)
                result = cleanRegex.stringByReplacingMatches(in: result, options: [], range: r, withTemplate: "$1$2$3")
            }
        }
        
        return result
    }
    
    /// Insert space between CJK and alphanumeric characters (Pangu Spacing)
    public func insertSpacingBetweenCJKAndAlphanumeric(_ text: String) -> String {
        var result = text
        
        // 1. CJK followed by alphanumeric
        let cjkAlphaPattern = "([\\u4e00-\\u9fa5])([a-zA-Z0-9])"
        if let regex = try? NSRegularExpression(pattern: cjkAlphaPattern, options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1 $2")
        }
        
        // 2. Alphanumeric followed by CJK
        let alphaCJKPattern = "([a-zA-Z0-9])([\\u4e00-\\u9fa5])"
        if let regex = try? NSRegularExpression(pattern: alphaCJKPattern, options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1 $2")
        }
        
        // Clean multiple consecutive spaces
        let multiSpacePattern = " +"
        if let regex = try? NSRegularExpression(pattern: multiSpacePattern, options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
        }
        
        return result.trimmingCharacters(in: .whitespaces)
    }
    
    /// Trim trailing punctuation for short phrases to facilitate ongoing typing
    public func trimTrailingPunctuationIfNeeded(_ text: String) -> String {
        var result = text
        let trailingPunctuationSet: CharacterSet = CharacterSet(charactersIn: "。，、；. ,;")
        
        if result.count < 30 {
            while let last = result.unicodeScalars.last, trailingPunctuationSet.contains(last) {
                result.removeLast()
            }
        }
        
        return result
    }
}
