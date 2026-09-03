import Foundation

/// Text layout, CJK-alphanumeric spacing, punctuation, and number normalization formatter
public final class TextFormatter {
    public static let shared = TextFormatter()
    
    public init() {}
    
    /// Full text formatting pipeline
    public func format(
        _ text: String,
        normalizeNumbers: Bool = true,
        insertCJKSpacing: Bool = true,
        removeStutter: Bool = true,
        trimTrailingPunctuation: Bool = true
    ) -> String {
        guard !text.isEmpty else { return text }
        
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Normalize spoken English/Chinese numbers to Arabic digits (0-9)
        if normalizeNumbers {
            result = normalizeNumbersToDigits(result)
        }
        
        // 2. Remove speech stutter and repetitions
        if removeStutter {
            result = deduplicateStutter(result)
        }
        
        // 3. Insert spacing between CJK and alphanumeric characters (Pangu Spacing)
        if insertCJKSpacing {
            result = insertSpacingBetweenCJKAndAlphanumeric(result)
        }
        
        // 4. Trim trailing punctuation for short phrases
        if trimTrailingPunctuation {
            result = trimTrailingPunctuationIfNeeded(result)
        }
        
        return result
    }
    
    // MARK: - Spoken Numbers to Arabic Digits Normalization
    
    /// Normalize spoken English and Chinese numbers into crisp Arabic numerals (0-9)
    public func normalizeNumbersToDigits(_ text: String) -> String {
        var result = text
        
        // 1. Phonetic speech typos for Mode 1, Mode 2 & common ASR glitches
        let speechAcroMap = [
            "Line mo Mailil": "Mode 1",
            "Line Mail": "Mode 1",
            "Line made": "Mode 1",
            "made one": "Mode 1",
            "me to": "Mode 2",
            "夢的兔": "Mode 2",
            "made two": "Mode 2",
            "IE S C": "Esc",
            "IE S": "Esc",
            "E S C": "Esc",
            "S C": "Esc",
            "八百多 M B": "800 多 MB",
            "八百多 MB": "800 多 MB",
            "八百 MB": "800 MB",
            "M B": "MB",
            "G B": "GB",
            "K B": "KB"
        ]
        for (typo, replacement) in speechAcroMap {
            result = result.replacingOccurrences(of: typo, with: replacement)
        }
        
        // 2. English hundreds & thousands
        let enHundreds: [(pattern: String, replacement: String)] = [
            ("(?i)\\bone\\s+hundred\\b", "100"),
            ("(?i)\\btwo\\s+hundred\\b", "200"),
            ("(?i)\\bthree\\s+hundred\\b", "300"),
            ("(?i)\\bfour\\s+hundred\\b", "400"),
            ("(?i)\\bfive\\s+hundred\\b", "500"),
            ("(?i)\\bsix\\s+hundred\\b", "600"),
            ("(?i)\\bseven\\s+hundred\\b", "700"),
            ("(?i)\\beight\\s+hundred\\b", "800"),
            ("(?i)\\bnine\\s+hundred\\b", "900"),
            ("(?i)\\bone\\s+thousand\\b", "1000"),
            ("(?i)\\btwo\\s+thousand\\b", "2000"),
            ("(?i)\\bthree\\s+thousand\\b", "3000"),
            ("(?i)\\bmode\\s+one\\b", "Mode 1"),
            ("(?i)\\bmode\\s+two\\b", "Mode 2"),
            ("(?i)\\bmode\\s+three\\b", "Mode 3")
        ]
        for item in enHundreds {
            if let regex = try? NSRegularExpression(pattern: item.pattern, options: []) {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: item.replacement)
            }
        }
        
        // 3. Chinese hundreds & thousands to digits
        let cnLargeNumbers = [
            ("九百", "900"),
            ("八百", "800"),
            ("七百", "700"),
            ("六百", "600"),
            ("五百", "500"),
            ("四百", "400"),
            ("三百", "300"),
            ("兩百", "200"),
            ("二百", "200"),
            ("一百", "100"),
            ("九千", "9000"),
            ("八千", "8000"),
            ("七千", "7000"),
            ("六千", "6000"),
            ("五千", "5000"),
            ("四千", "4000"),
            ("三千", "3000"),
            ("兩千", "2000"),
            ("二千", "2000"),
            ("一千", "1000")
        ]
        for (cn, digit) in cnLargeNumbers {
            result = result.replacingOccurrences(of: cn, with: digit)
        }
        
        // 4. Quantifiers with units (e.g. "第一點" -> "第 1 點", "第二點" -> "第 2 點", "第800" -> "第 800")
        let quantifierUnits = [
            ("第一點", "第 1 點"),
            ("第二點", "第 2 點"),
            ("第三點", "第 3 點"),
            ("第四點", "第 4 點"),
            ("第五點", "第 5 點"),
            ("第六點", "第 6 點"),
            ("第七點", "第 7 點"),
            ("第八點", "第 8 點"),
            ("第九點", "第 9 點"),
            ("第十點", "第 10 點"),
            ("Mode 一", "Mode 1"),
            ("Mode 二", "Mode 2"),
            ("Mode 三", "Mode 3")
        ]
        for (cn, digit) in quantifierUnits {
            result = result.replacingOccurrences(of: cn, with: digit)
        }
        
        return result
    }
    
    // MARK: - Stutter Deduplication
    
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
    
    // MARK: - Pangu Spacing
    
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
    
    // MARK: - Trailing Punctuation
    
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
