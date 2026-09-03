import Foundation

/// Intelligent text polishing, contextual homophone correction, filler word removal, and Typeless-grade note structuring engine
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
        
        // 2. Normalize spoken numbers & unit abbreviations
        var normalized = TextFormatter.shared.normalizeNumbersToDigits(traditional)
        normalized = TextFormatter.shared.normalizeUnitsAndTechTerms(normalized)
        
        // 3. Deep contextual homophone & tech terms correction
        normalized = correctContextualHomophones(normalized)
        normalized = normalizePhoneticTypos(normalized)
        
        // 4. Remove multi-clause progressive stutters and immediate repetitions
        normalized = removeStutterAndRepetitions(normalized)
        
        // 5. Remove conversational filler words and oral crutches
        normalized = removeFillerWords(normalized, aggressive: mode != .liveStream)
        
        // 6. Clean messy and consecutive punctuation marks
        normalized = cleanPunctuation(normalized)
        
        // 7. Apply structural organization based on mode (Typeless-grade structuring)
        let structured: String
        switch mode {
        case .liveStream:
            structured = normalized
        case .structuredNote, .conciseSummary:
            structured = structureIntoTypelessNotes(normalized)
        }
        
        // 8. Insert spacing between CJK and alphanumeric characters (Pangu Spacing)
        let formatted = TextFormatter.shared.insertSpacingBetweenCJKAndAlphanumeric(structured)
        
        return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Contextual Homophone Correction
    
    /// Context-aware disambiguation for spoken homophones and technical jargon
    public func correctContextualHomophones(_ text: String) -> String {
        var result = text
        
        // Regex patterns for context-dependent corrections
        let contextualRegexes: [(pattern: String, replacement: String)] = [
            ("羽翼(?=如果|明顯|表達|理解|上下文|順序|判定)", "語意"),
            ("(稍微|多|幫我|進行|文字|文章|內容)認識", "$1潤飾"),
            ("認識(?=文字|文章|一下|的多一點|一下下|的|內容)", "潤飾"),
            ("Speech\\s+(the\\s+talk|to|the)\\s+Text|switch\\s+t\\s+Text", "Speech-to-Text"),
            ("前後的康泰|前後的\\s*context|前後的\\s*康泰克斯", "前後文的 Context"),
            ("康泰克斯|康泰(?=[可以|能夠|去做|分析])", "Context"),
            ("這兩個\\s*(mall|mode|毛|Mo)", "這兩個 Mode"),
            ("第二個\\s*(ml|mode|毛|Mo)\\s*的?", "第二個 Mode "),
            ("夢的圖|莫德圖|莫得圖", "Mode 2"),
            ("莫德萬|莫得萬|夢的萬|墨的萬", "Mode 1"),
            ("live\\s*saving|streamDreamin|Live\\s*Streaming\\s*streamDreamin", "Live Streaming"),
            ("messMessa\\s*messge\\s*mess\\s*RadarMadara|RadarMadara\\s*game\\s*getMadara", "Message"),
            ("Mata\\s*bite|Meta\\s*bite", "MB"),
            ("音譜|應譜", "Input"),
            ("奧普|奧特普", "Output"),
            ("L\\s*O\\s*C\\s*O|L\\s*O\\s*C\\s*A\\s*L|(?i)\\bLoco\\b", "Local"),
            ("壞\\s*List|What\\s*last|what\\s*list|壞名單", "Whitelist"),
            ("com\\s*一版|come\\s*一版", "Commit 一版"),
            ("扣核心", "Core 核心"),
            ("收\\s*call|so\\s*call|so\\s*co", "Source Code"),
            ("哈扣寫|哈扣", "Hardcode"),
            ("拍森|拍省", "Python"),
            ("secret\\s*stone|istema\\s*stone|the\\s*season\\s*Prom|the\\s*season\\s*Pro|season\\s*Prom|Theakston\\s*Brown|Theakston|brown\\s*所以", "System Prompt"),
            ("塞\\s*(the\\s*season\\s*Prom|the\\s*season\\s*Pro|season\\s*Prom|season\\s*Pro|the\\s*season|Prompt|Prom|Pro)", "塞 System Prompt"),
            ("把蚊子", "把文字"),
            ("布拉布布拉|不拉布拉|布拉布拉", "等等"),
            ("字字", "字"),
            ("段類", "段之類"),
            ("類類", "類"),
            ("夠夠", "夠"),
            ("別別", "別")
        ]
        
        for item in contextualRegexes {
            if let regex = try? NSRegularExpression(pattern: item.pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: item.replacement)
            }
        }
        
        return result
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
            "第二二點": "第 2 點",
            "第一一點": "第 1 點",
            "第三三點": "第 3 點",
            "認識認識": "潤飾",
            "所做的西西": "所做的東西",
            "整理過字": "整理過的字",
            "像對是": "相對是",
            "之什麼之後呢": "之後",
            "然後呢然後": "然後",
            "我也不知道我也不知道": "我也不知道",
            "一模一樣一模一樣": "一模一樣",
            "順序順序": "順序",
            "希望希望": "希望",
            "文字字": "文字"
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
    
    /// Remove progressive clause stutters and character/phrase repetitions
    public func removeStutterAndRepetitions(_ text: String) -> String {
        var result = text
        
        // 1. Repetitive restarting clauses (e.g. "好，我再來試次，好我再試一次，好，我再試一次" -> "好，我再試一次，")
        let restartPatterns = [
            ("(好[，、\\s]*我[再來|再]*試[一次|次]*[，、\\s]*)+", "好，我再試一次，"),
            ("(看[看]*能[不]*[，、\\s]*就是看能不能[錯別字別|把錯別字去]*[，、\\s]*)+", "看能不能把錯別字去掉，"),
            ("是錯的。[，、\\s\n]*但是因為你知道", "但是因為你知道")
        ]
        for (pat, rep) in restartPatterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: []) {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: rep)
            }
        }
        
        // 2. Progressive prefix clause stutter (e.g. "好我們來，好我們來測試" -> "好我們來測試")
        let progressivePrefixPattern = "([，。！？\n\\s]|^)([\\u4e00-\\u9fa5A-Za-z0-9]{2,15})[，、\\s]+(?=\\2)"
        if let regex = try? NSRegularExpression(pattern: progressivePrefixPattern, options: []) {
            for _ in 0..<3 {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
            }
        }
        
        // 3. Repeated full sentence deduplication (e.g. "盡可能地去呈現。盡可能地去呈現" -> "盡可能地去呈現。")
        let sentenceRepeatPattern = "([^\\n。！？]{4,40}[。！？])[，、\\s]*\\1"
        if let regex = try? NSRegularExpression(pattern: sentenceRepeatPattern, options: []) {
            for _ in 0..<2 {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
            }
        }
        
        // 4. Single character repeated 3+ times (e.g. "我我我" -> "我")
        let triplePattern = "([\\u4e00-\\u9fa5])\\1{2,}"
        if let regex = try? NSRegularExpression(pattern: triplePattern, options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }
        
        // 5. Remove 2-character stutter pronouns/conjunctions at phrase starts (e.g. "我我覺得" -> "我覺得")
        let cleanPattern = "([，。！？\n\\s]|^)(我|這|那|但|就|如|連|是|很|剛)\\2([\\u4e00-\\u9fa5])"
        if let cleanRegex = try? NSRegularExpression(pattern: cleanPattern, options: []) {
            let r = NSRange(location: 0, length: result.utf16.count)
            result = cleanRegex.stringByReplacingMatches(in: result, options: [], range: r, withTemplate: "$1$2$3")
        }
        
        // 6. Two-character words repeated (e.g. "這個這個" -> "這個", "然後然後" -> "然後")
        let doubleCharPattern = "([\\u4e00-\\u9fa5]{2})\\1+"
        if let regex = try? NSRegularExpression(pattern: doubleCharPattern, options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }
        
        // 7. Multi-character phrase repetitions (2 to 10 characters, e.g. "我們試試看我們試試看" -> "我們試試看")
        let multiPhrasePattern = "([\\u4e00-\\u9fa5A-Za-z0-9]{2,10})\\1+"
        if let regex = try? NSRegularExpression(pattern: multiPhrasePattern, options: []) {
            for _ in 0..<2 {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
            }
        }
        
        // 8. Repeated phrases separated by comma or space (e.g. "你真的覺得，你真的覺得" -> "你真的覺得")
        let commaPhrasePattern = "([\\u4e00-\\u9fa5A-Za-z0-9]{2,12})[，、\\s]+\\1"
        if let regex = try? NSRegularExpression(pattern: commaPhrasePattern, options: []) {
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
        let transitionBreakPattern = "，(?=(另外|此外|不過|但是|然而|因此|總結來說|總之|第一點|第二點|第三點|首先|其次|最後|第 1 點|第 2 點|第 3 點))"
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
        let listPattern = "(?<=[。！？\n]|^|，)\\s*(第一種模式|第二種模式|第\\s*[一二三四五六七八九十0-9]+\\s*[點個項件、，事]|首先|一來|其次|二來|再來|最後[一點項事]?|總結來說|總結[：:]?|另外[一點項件事]?|此外[一點項件事]?)"
        
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
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: "。！？\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard sentences.count > 1 else {
            return text.hasSuffix("。") || text.hasSuffix("！") || text.hasSuffix("？") ? text : text + "。"
        }
        
        var paragraphs: [String] = []
        var currentParagraph: [String] = []
        
        let transitionKeywords = ["另外", "此外", "不過", "但是", "然而", "因此", "總結來說", "總之", "總結", "最後", "也就是", "而且", "你看像", "所以"]
        
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
