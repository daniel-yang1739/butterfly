import Foundation

/// Intelligent text polishing, filler word removal, and note structuring engine
public final class TextPolisher {
    public static let shared = TextPolisher()
    
    public init() {}
    
    /// Polishing modes
    public enum PolishMode: String, CaseIterable, Sendable {
        case liveStream = "live"             // Real-time dictation: light filler cleaning, fast output
        case structuredNote = "structured"   // Record & Polish: deep filler cleaning, auto-paragraphing, bullet point extraction
        case conciseSummary = "concise"     // Summary mode: concise wording, colloquial removal
    }
    
    /// Main polishing and formatting pipeline
    public func polish(_ text: String, mode: PolishMode = .structuredNote) -> String {
        guard !text.isEmpty else { return text }
        
        // 1. Ensure 100% Traditional Chinese (Taiwan standard)
        let traditional = OpenCCTranslator.shared.convert(text)
        
        // 2. Remove stutters and immediate repetitions
        var cleaned = removeStutterAndRepetitions(traditional)
        
        // 3. Remove conversational filler words
        cleaned = removeFillerWords(cleaned, aggressive: mode != .liveStream)
        
        // 4. Clean messy and consecutive punctuation marks
        cleaned = cleanPunctuation(cleaned)
        
        // 5. Apply structural organization based on mode
        let structured: String
        switch mode {
        case .liveStream:
            structured = cleaned
        case .structuredNote, .conciseSummary:
            structured = structureIntoNotes(cleaned)
        }
        
        // 6. Insert spacing between CJK and alphanumeric characters (Pangu Spacing)
        let formatted = TextFormatter.shared.insertSpacingBetweenCJKAndAlphanumeric(structured)
        
        return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Filler Word Filtering
    
    /// Remove conversational filler words and redundant particles
    public func removeFillerWords(_ text: String, aggressive: Bool = false) -> String {
        var result = text
        
        // 1. Multi-word conversational fillers
        let multiWordFillers = [
            "那個那個": "",
            "就是說那個": "就是說",
            "怎麼說呢": "",
            "老實說啦": "",
            "老實說": "",
            "基本上來說": "",
            "對對對": "對",
            "是是是": "是",
            "好不好啊": "",
            "然後呢然後": "然後",
            "然後呢": aggressive ? "" : "接著"
        ]
        for (filler, replacement) in multiWordFillers {
            result = result.replacingOccurrences(of: filler, with: replacement)
        }
        
        // 2. Leading conversational fillers at sentence starts or after punctuation
        let leadingFillerPattern = "([，。！？\n]|^)\\s*(呃+|嗯+|啊+|哦+|噢+|唔+|欸+|呀+|那個+|就是說|我跟你說|話說回來)+[，、\\s]*"
        if let regex = try? NSRegularExpression(pattern: leadingFillerPattern, options: []) {
            for _ in 0..<3 { // Run multiple passes to clean composite fillers
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
            }
        }
        
        // 3. Trailing conversational particles before punctuation (only in aggressive note polishing mode)
        if aggressive {
            let trailingFillerPattern = "(?<=[\\u4e00-\\u9fa5]{2})[，\\s]*(啦|咧|吧|呢|呀|喔|噢|哈)+(?=[，。！？\n]|$)"
            if let regex = try? NSRegularExpression(pattern: trailingFillerPattern, options: []) {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }
        
        // 4. Isolated filler particles enclosed by punctuation or whitespace
        let isolatedFillerPattern = "(?<=[，。！？、\\s])[呃嗯欸喔噢唔呀咧]+(?=[，。！？、\\s])"
        if let regex = try? NSRegularExpression(pattern: isolatedFillerPattern, options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        
        return result
    }
    
    // MARK: - Stutter & Repetition Removal
    
    /// Remove stuttering and consecutive character/word repetitions
    public func removeStutterAndRepetitions(_ text: String) -> String {
        var result = text
        
        // 1. Single character repeated 3+ times (e.g. "我我我" -> "我")
        let triplePattern = "([\\u4e00-\\u9fa5])\\1{2,}"
        if let regex = try? NSRegularExpression(pattern: triplePattern, options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }
        
        // 2. Remove 2-character stutter pronouns/conjunctions at phrase starts (e.g. "我我覺得" -> "我覺得")
        let cleanPattern = "([，。！？\n\\s]|^)(我|這|那|但|就|如)\\2([\\u4e00-\\u9fa5])"
        if let cleanRegex = try? NSRegularExpression(pattern: cleanPattern, options: []) {
            let r = NSRange(location: 0, length: result.utf16.count)
            result = cleanRegex.stringByReplacingMatches(in: result, options: [], range: r, withTemplate: "$1$2$3")
        }
        
        // 3. Two-character words repeated (e.g. "這個這個" -> "這個", "然後然後" -> "然後")
        let doubleCharPattern = "([\\u4e00-\\u9fa5]{2})\\1+"
        if let regex = try? NSRegularExpression(pattern: doubleCharPattern, options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }
        
        return result
    }
    
    // MARK: - Punctuation Cleanup
    
    /// Clean duplicate and invalid punctuation sequences
    public func cleanPunctuation(_ text: String) -> String {
        var result = text
        
        let duplicatePunctPatterns = [
            ("，+", "，"),
            ("。+", "。"),
            ("！+", "！"),
            ("？+", "？"),
            ("、+", "、"),
            ("，。|。，", "。"),
            ("^[，、。！？\\s]+", "")
        ]
        
        for (pattern, replacement) in duplicatePunctPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement)
            }
        }
        
        return result
    }
    
    // MARK: - Intelligent Structuring & Bullet Points
    
    /// Structure spoken monologue into formatted notes with bullet points and paragraphs
    public func structureIntoNotes(_ text: String) -> String {
        guard text.count > 15 else { return text }
        
        let listIndicators = ["第一", "首先", "一來", "第二", "其次", "二來", "第三", "再來", "最後", "總結", "另外", "此外", "還有一個", "一種模式", "第二種模式"]
        let hasListIndicators = listIndicators.filter { text.contains($0) }.count >= 2
        
        if hasListIndicators {
            return formatAsBulletPoints(text)
        } else {
            return formatAsParagraphs(text)
        }
    }
    
    /// Format enumerated speech markers into Markdown bullet list items
    public func formatAsBulletPoints(_ text: String) -> String {
        let splitPattern = "(?<=[。！？\n]|^|，)\\s*(第一種模式|第二種模式|第[一二三四五六七八九十0-9]+[點個項件、，事]|首先|一來|其次|二來|再來|最後[一點項事]?|總結來說|總結[：:]?|另外[一點項件事]?|此外[一點項件事]?|還有一個是|還有[：:]?)"
        
        guard let regex = try? NSRegularExpression(pattern: splitPattern, options: []) else {
            return formatAsParagraphs(text)
        }
        
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        
        guard matches.count >= 2 else {
            return formatAsParagraphs(text)
        }
        
        var points: [String] = []
        var prefixText = ""
        
        let firstMatchLocation = matches[0].range.location
        if firstMatchLocation > 0 {
            prefixText = nsString.substring(with: NSRange(location: 0, length: firstMatchLocation))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "，、。；"))
        }
        
        for i in 0..<matches.count {
            let start = matches[i].range.location
            let end = (i + 1 < matches.count) ? matches[i + 1].range.location : text.utf16.count
            let length = max(0, end - start)
            
            var item = nsString.substring(with: NSRange(location: start, length: length))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "，、；"))
            
            if !item.isEmpty && !item.hasSuffix("。") && !item.hasSuffix("！") && !item.hasSuffix("？") {
                item += "。"
            }
            
            if !item.isEmpty {
                points.append("- " + item)
            }
        }
        
        var output = ""
        if !prefixText.isEmpty {
            output += prefixText + "：\n\n"
        }
        output += points.joined(separator: "\n")
        
        return output
    }
    
    /// Break monologue into clean logical paragraphs
    public func formatAsParagraphs(_ text: String) -> String {
        let sentencePattern = "([^。！？\n]+[。！？])"
        guard let regex = try? NSRegularExpression(pattern: sentencePattern, options: []) else {
            return text
        }
        
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        
        if matches.count <= 2 {
            return text
        }
        
        var paragraphs: [String] = []
        var currentParagraph: [String] = []
        
        let transitionKeywords = ["另外", "此外", "不過", "但是", "然而", "因此", "總結來說", "總之", "總結", "最後"]
        
        for match in matches {
            let sentence = nsString.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty else { continue }
            
            let isTransition = transitionKeywords.contains { sentence.hasPrefix($0) }
            
            if isTransition && !currentParagraph.isEmpty {
                paragraphs.append(currentParagraph.joined())
                currentParagraph = [sentence]
            } else {
                currentParagraph.append(sentence)
                if currentParagraph.count >= 3 {
                    paragraphs.append(currentParagraph.joined())
                    currentParagraph = []
                }
            }
        }
        
        if !currentParagraph.isEmpty {
            paragraphs.append(currentParagraph.joined())
        }
        
        return paragraphs.joined(separator: "\n\n")
    }
}
