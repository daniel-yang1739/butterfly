import Foundation

/// Text layout, CJK-alphanumeric spacing, punctuation, and number/unit normalization formatter
public final class TextFormatter {
    public static let shared = TextFormatter()
    
    public init() {}
    
    /// Full text formatting pipeline
    public func format(
        _ text: String,
        normalizeNumbersAndUnits: Bool = true,
        insertCJKSpacing: Bool = true,
        removeStutter: Bool = false,
        trimTrailingPunctuation: Bool = false
    ) -> String {
        guard !text.isEmpty else { return text }
        
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Normalize spoken English/Chinese numbers and metric/digital units
        if normalizeNumbersAndUnits {
            result = normalizeNumbersToDigits(result)
            result = normalizeUnitsAndTechTerms(result)
        }
        
        // 2. Remove speech stutter and repetitions
        if removeStutter {
            result = deduplicateStutter(result)
        }
        
        // 3. Insert spacing between CJK and alphanumeric characters (Pangu Spacing)
        if insertCJKSpacing {
            result = insertSpacingBetweenCJKAndAlphanumeric(result)
        }
        
        // 4. Trim trailing punctuation only if explicitly requested
        if trimTrailingPunctuation {
            result = trimTrailingPunctuationIfNeeded(result)
        }
        
        return result
    }
    
    // MARK: - Spoken Numbers to Arabic Digits Normalization
    
    /// Normalize spoken English and Chinese numbers into crisp Arabic numerals (0-9)
    public func normalizeNumbersToDigits(_ text: String) -> String {
        var result = text
        
        // 1. English hundreds & thousands
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
            ("(?i)\\bv\\s*(?:one|1)\\b", "V1"),
            ("(?i)\\bv\\s*(?:two|2)\\b", "V2"),
            ("(?i)\\bv\\s*(?:three|3)\\b", "V3"),
            ("(?i)\\bv\\s*(?:four|4)\\b", "V4"),
            ("(?i)\\bv\\s*(?:five|5)\\b", "V5")
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
        
        // 4. Quantifiers with units (e.g. "第一點" -> "第 1 點", "第二點" -> "第 2 點")
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
    
    // MARK: - Unit & Tech Terms Normalization
    
    /// Normalize spoken technical, memory, metric, and time units into standard abbreviations
    public func normalizeUnitsAndTechTerms(_ text: String) -> String {
        var result = text
        
        // 1. Spoken Digital Storage Units (Mega bite, Giga bite, etc.)
        let spokenUnits = [
            ("Tarab bite", "TB"),
            ("tara bite", "TB"),
            ("Tara bite", "TB"),
            ("tarabyte", "TB"),
            ("Mega bite", "MB"),
            ("mega bite", "MB"),
            ("Giga bite", "GB"),
            ("giga bite", "GB"),
            ("Kilo bite", "KB"),
            ("kilo bite", "KB")
        ]
        for (unit, replacement) in spokenUnits {
            result = result.replacingOccurrences(of: unit, with: replacement)
        }
        
        // 2. Common Spoken Dev Acoustic Slips & Phonetic Jargon
        let devAcousticSlips: [(pattern: String, replacement: String)] = [
            ("(?i)\\b(?:V\\s*1|V\\s*one|B\\s*one|B1)\\s*(?:Chuck\\s*later|can\\s*later|chance\\s*later)\\b", "V1 Translator"),
            ("(?i)\\b(?:com\\s*meet|com\\s*mit|co\\s*meet)\\b", "Commit"),
            ("(?i)\\b(?:get\\s*hub|get\\s*hop|gget\\s*hop|gget\\s*top)\\b", "GitHub"),
            ("(?i)\\b(?:brandes|branchs)\\b", "Branches")
        ]
        for slip in devAcousticSlips {
            if let regex = try? NSRegularExpression(pattern: slip.pattern, options: []) {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: slip.replacement)
            }
        }
        
        // 3. Unit regexes (Digital, Metric, Time, Frequency)
        let unitPatterns: [(pattern: String, replacement: String)] = [
            ("(?i)\\b(megabytes?|mega\\s*bytes?)\\b", "MB"),
            ("(?i)\\b(gigabytes?|giga\\s*bytes?)\\b", "GB"),
            ("(?i)\\b(terabytes?|tera\\s*bytes?)\\b", "TB"),
            ("(?i)\\b(kilobytes?|kilo\\s*bytes?)\\b", "KB"),
            ("(?i)\\b(petabytes?|peta\\s*bytes?)\\b", "PB"),
            ("(?i)\\b(kilograms?|kilo\\s*grams?|kilos?)\\b", "kg"),
            ("(?i)\\b(grams?)\\b", "g"),
            ("(?i)\\b(milligrams?|milli\\s*grams?)\\b", "mg"),
            ("(?i)\\b(kilometers?|kilo\\s*meters?)\\b", "km"),
            ("(?i)\\b(centimeters?|centi\\s*meters?)\\b", "cm"),
            ("(?i)\\b(millimeters?|milli\\s*meters?)\\b", "mm"),
            ("(?i)\\b(milliseconds?|milli\\s*seconds?)\\b", "ms"),
            ("(?i)\\b(microseconds?|micro\\s*seconds?)\\b", "µs"),
            ("(?i)\\b(nanoseconds?|nano\\s*seconds?)\\b", "ns"),
            ("(?i)\\b(frames?\\s*per\\s*second)\\b", "FPS"),
            ("(?i)\\b(percentages?|percents?)\\b", "%")
        ]
        
        for item in unitPatterns {
            if let regex = try? NSRegularExpression(pattern: item.pattern, options: []) {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: item.replacement)
            }
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
