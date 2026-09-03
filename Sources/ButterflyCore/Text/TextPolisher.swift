import Foundation

/// Intelligent text polishing, filler word removal, and Typeless-grade note structuring engine
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        // 1. Ensure 100% Traditional Chinese (Taiwan standard)
        let traditional = OpenCCTranslator.shared.convert(trimmed)
        
        // 2. Normalize phonetic homophones and common speech recognition artifacts
        var normalized = normalizePhoneticTypos(traditional)
        
        // 3. Remove stutters, repeated characters, and duplicated phrases
        normalized = removeStutterAndRepetitions(normalized)
        
        // 4. Remove conversational filler words and oral crutches
        normalized = removeFillerWords(normalized, aggressive: mode != .liveStream)
        
        // 5. Clean messy and consecutive punctuation marks
        normalized = cleanPunctuation(normalized)
        
        // 6. Apply structural organization based on mode (Typeless-grade structuring)
        let structured: String
        switch mode {
        case .liveStream:
            structured = normalized
        case .structuredNote, .conciseSummary:
            structured = structureIntoTypelessNotes(normalized)
        }
        
        // 7. Insert spacing between CJK and alphanumeric characters (Pangu Spacing)
        let formatted = TextFormatter.shared.insertSpacingBetweenCJKAndAlphanumeric(structured)
        
        return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Phonetic & Colloquial Normalization
    
    /// Normalize frequent phonetic homophones and code-switching errors
    public func normalizePhoneticTypos(_ text: String) -> String {
        var result = text
        
        let typoMap = [
            "S C N S C": "Esc",
            "yes C": "Esc",
            "S C": "Esc",
            "E S C": "Esc",
            "lifetime": "Live Streaming",
            "Line streaming": "Live Streaming",
            "line streaming": "Live Streaming",
            "stm": "Streaming",
            "sting": "Streaming",
            "typees": "Typeless",
            "Temples": "Typeless",
            "T Y P E L E S S": "Typeless",
            "郵輪邏輯": "邏輯",
            "於最近": "贅字",
            "拗不出來": "Output 出來",
            "拗出來": "Output 出來",
            "雜雜訊": "雜訊",
            "雜項": "雜訊",
            "第二二點": "第二點",
            "第一一點": "第一點",
            "第三三點": "第三點",
            "認識認識": "潤飾",
            "所做的西西": "所做的東西",
            "整理過字": "整理過的字",
            "像對是": "相對是",
            "之什麼之後呢": "之後",
            "然後呢然後": "然後",
            "我也不知道我也不知道": "我也不知道",
            "一模一樣一模一樣": "一模一樣",
            "順序順序": "順序",
            "希望希望": "希望"
        ]
        
        for (typo, replacement) in typoMap {
            result = result.replacingOccurrences(of: typo, with: replacement)
        }
        
        return result
    }
    
    // MARK: - Filler Word Filtering
    
    /// Remove conversational filler words and redundant particles
    public func removeFillerWords(_ text: String, aggressive: Bool = false) -> String {
        var result = text
        
        // 1. Multi-word conversational fillers
        let multiWordFillers = [
            "那個那個": "",
            "就是說那個": "",
            "怎麼說呢": "",
            "老實說啦": "",
            "老實說": "",
            "基本上來說": "",
            "基本上": "",
            "對對對": "對",
            "是是是": "是",
            "好不好啊": "",
            "好不好": "",
            "這樣那": "",
            "我跟你講": "",
            "我跟你說": "",
            "應該說": aggressive ? "" : "應該說",
            "就是說": aggressive ? "" : "即",
            "然後呢": aggressive ? "，" : "接著",
            "之後呢": aggressive ? "，" : "接著"
        ]
        for (filler, replacement) in multiWordFillers {
            result = result.replacingOccurrences(of: filler, with: replacement)
        }
        
        // 2. Leading conversational fillers at sentence starts or after punctuation
        let leadingFillerPattern = "([，。！？\n]|^)\\s*(呃+|嗯+|啊+|哦+|噢+|唔+|欸+|呀+|那個+|就是說|話說回來|那也就是)+[，、\\s]*"
        if let regex = try? NSRegularExpression(pattern: leadingFillerPattern, options: []) {
            for _ in 0..<3 {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
            }
        }
        
        // 3. Trailing conversational particles before punctuation (in aggressive note polishing mode)
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
        let cleanPattern = "([，。！？\n\\s]|^)(我|這|那|但|就|如|連|是|很|剛)\\2([\\u4e00-\\u9fa5])"
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
    
    // MARK: - Punctuation Cleanup & Sentence Normalization
    
    /// Clean duplicate and invalid punctuation sequences and normalize run-on commas
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
        
        // Convert trailing conjunction commas before transition keywords into full stops
        let transitionBreakPattern = "，(?=(另外|此外|不過|但是|然而|因此|總結來說|總之|第一點|第二點|第三點|首先|其次|最後))"
        if let regex = try? NSRegularExpression(pattern: transitionBreakPattern, options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "。")
        }
        
        return result
    }
    
    // MARK: - Typeless-Grade Note Structuring
    
    /// Structure spoken monologue into formatted notes with bullet points and paragraphs
    public func structureIntoTypelessNotes(_ text: String) -> String {
        guard text.count > 15 else { return text }
        
        // 1. Check for enumerated list indicators
        let listPattern = "(?<=[。！？\n]|^|，)\\s*(第一種模式|第二種模式|第[一二三四五六七八九十0-9]+[點個項件、，事]|首先|一來|其次|二來|再來|最後[一點項事]?|總結來說|總結[：:]?|另外[一點項件事]?|此外[一點項件事]?)"
        
        if let regex = try? NSRegularExpression(pattern: listPattern, options: []) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            
            // If 2 or more distinct bullet markers exist, construct a structured Markdown document
            if matches.count >= 2 {
                var sections: [String] = []
                
                // A. Introductory paragraph (everything before the first list item)
                let firstMatchLoc = matches[0].range.location
                if firstMatchLoc > 0 {
                    let intro = nsString.substring(with: NSRange(location: 0, length: firstMatchLoc))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "，、。；"))
                    if !intro.isEmpty {
                        sections.append(formatAsParagraphs(intro))
                    }
                }
                
                // B. Bullet points
                var bulletPoints: [String] = []
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
                        bulletPoints.append("- " + item)
                    }
                }
                
                if !bulletPoints.isEmpty {
                    sections.append(bulletPoints.joined(separator: "\n"))
                }
                
                return sections.joined(separator: "\n\n")
            }
        }
        
        // 2. Default: Split into clean, logical paragraphs (2-3 sentences each)
        return formatAsParagraphs(text)
    }
    
    /// Break monologue into clean logical paragraphs
    public func formatAsParagraphs(_ text: String) -> String {
        // Split by full stops, exclamation marks, question marks, or double commas
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: "。！？\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard sentences.count > 1 else {
            return text.hasSuffix("。") || text.hasSuffix("！") || text.hasSuffix("？") ? text : text + "。"
        }
        
        var paragraphs: [String] = []
        var currentParagraph: [String] = []
        
        let transitionKeywords = ["另外", "此外", "不過", "但是", "然而", "因此", "總結來說", "總之", "總結", "最後", "也就是", "而且", "你看像"]
        
        for sentence in sentences {
            let cleanSentence = sentence.hasSuffix("。") || sentence.hasSuffix("！") || sentence.hasSuffix("？") ? sentence : sentence + "。"
            let isTransition = transitionKeywords.contains { cleanSentence.hasPrefix($0) }
            
            if isTransition && !currentParagraph.isEmpty {
                paragraphs.append(currentParagraph.joined())
                currentParagraph = [cleanSentence]
            } else {
                currentParagraph.append(cleanSentence)
                if currentParagraph.count >= 2 {
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
