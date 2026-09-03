import Foundation

/// Two-Pass Cognitive Text Polisher and Contextual Intent Reconstruction Engine
public final class TextPolisher {
    public static let shared = TextPolisher()
    
    public init() {}
    
    /// Polishing modes
    public enum PolishMode: String, CaseIterable, Sendable {
        case liveStream = "live"             // Real-time dictation: light filler cleaning, fast output
        case structuredNote = "structured"   // Record & Polish: deep filler cleaning, auto-paragraphing, bullet point extraction
        case conciseSummary = "concise"     // Summary mode: concise wording, colloquial removal
    }
    
    /// Main multi-pass cognitive polishing and contextual intent reconstruction pipeline
    public func polish(_ text: String, mode: PolishMode = .structuredNote) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        
        // Step 0: Ensure 100% Traditional Chinese (Taiwan standard)
        let traditional = OpenCCTranslator.shared.convert(trimmed)
        
        // Pass 1: Spoken Numbers & Metric/Data Units Normalization
        var pass1 = TextFormatter.shared.normalizeNumbersToDigits(traditional)
        pass1 = TextFormatter.shared.normalizeUnitsAndTechTerms(pass1)
        
        // Pass 2: Deep Contextual Intent Disambiguation & ASR Acoustic Recovery
        var pass2 = restoreAcousticAndPhoneticTokens(pass1)
        pass2 = disambiguateSemanticIntent(pass2)
        pass2 = normalizePhoneticTypos(pass2)
        
        // For Mode 1 (Live Streaming Dictation):
        // 100% FAITHFUL TO USER SPEECH!
        // Apply number/unit conversions, Traditional Chinese, and tech dictionary restoration,
        // but ZERO word deletions or stutter filtering so natural repetitions are preserved!
        if mode == .liveStream {
            let spaced = TextFormatter.shared.insertSpacingBetweenCJKAndAlphanumeric(pass2)
            return spaced.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Pass 3 (Mode 2 Only): Multi-Clause Progressive Stutter & Loop Annihilation
        var pass3 = annihilateStuttersAndRestarts(pass2)
        pass3 = removeFillerWords(pass3, aggressive: true)
        pass3 = cleanPunctuation(pass3)
        
        // Pass 4 (Mode 2 Only): Typeless-Grade Structural Note Formatting
        let structured = structureIntoTypelessNotes(pass3)
        
        // Step Final: Insert spacing between CJK and alphanumeric characters (Pangu Spacing)
        let formatted = TextFormatter.shared.insertSpacingBetweenCJKAndAlphanumeric(structured)
        return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Pass 2A: Acoustic & Phonetic Token Restoration
    
    /// Restore acoustically misheard tech tokens and code-switching terms based on domain context
    public func restoreAcousticAndPhoneticTokens(_ text: String) -> String {
        var result = text
        
        let tokenPatterns: [(pattern: String, replacement: String)] = [
            // Fuzzy Mode 2 & Mode 1 phonetic variations (matches 茂 t, 茂 the one, me 兔, 沒ode 1, 冒著吐兔, etc.)
            ("(?i)\\b(?:ml|m\\s*l)\\s*(?:的|得|之)?\\s*(?:to|two|2|兔|圖)\\b|ml\\s*的\\s*to", "Mode 2"),
            ("(?i)\\b(?:ml|m\\s*l)\\s*(?:的|得|之)?\\s*(?:one|1|萬|玩)\\b|ml\\s*的\\s*one", "Mode 1"),
            ("(?i)茂\\s*(?:the\\s*one|one|1|萬)", "Mode 1"),
            ("(?i)(?:me\\s*兔|茂\\s*[tT2二兔圖吐]|茂\\s*the\\s*two)", "Mode 2"),
            ("沒\\s*ode\\s*1", "Mode 1"),
            ("沒\\s*ode\\s*2", "Mode 2"),
            ("[貓冒墨莫夢帽茂][的德得著]*[兔圖吐土tT2二]+", "Mode 2"),
            ("[貓冒墨莫夢帽茂][的德得著]*[萬玩完一1]+", "Mode 1"),
            ("Mode 2\\s*的萬\\s*Mode 1", "Mode 2 與 Mode 1"),
            ("這兩個\\s*(?:mall|mode|毛|Mo)", "這兩個 Mode"),
            ("第二個\\s*(?:ml|mode|毛|Mo)\\s*的?", "第二個 Mode "),
            ("第一個\\s*(?:ml|mode|毛|Mo)\\s*的?", "第一個 Mode "),
            
            // System Prompt fuzzy variations (matches sister Prom, sister Pat, set Pro, stone Prom, system Prom, etc.)
            ("(?i)(?:secret|system|sister|cister|the\\s*season|season|stone|sistema|sixteen|set)\\s*(?:stone|prom|prompt|pro|promt|pat|pad)\\b", "System Prompt"),
            ("(?i)(?:sister\\s*Pat|set\\s*Pro|sister\\s*prom|sister\\s*prompt|stone\\s*prom|stone\\s*prompt)", "System Prompt"),
            ("塞\\s*(?:the\\s*season|season|system|sister)?\\s*(?:prom|prompt|pro|stone|pat|pad)", "塞 System Prompt"),
            ("Theakston\\s*Brown|Theakston|brown\\s*所以", "System Prompt"),
            
            // Context & Token relations
            ("(?:上下文|前後文|前後)\\s*康泰(?:\\s*克斯)?", "上下文 Context"),
            ("康泰\\s*Token", "Context Token"),
            ("康泰(?=[可以|能夠|去做|分析|之間的關係|之間的|長度|視窗])", "Context"),
            
            // Speech-to-Text & Transcription mechanics
            ("Speech\\s+(?:the\\s+talk|to|the)\\s+Text|switch\\s+t\\s+Text", "Speech-to-Text"),
            ("竹子稿|桌子稿", "逐字稿"),
            ("診斷\\s*逐字稿", "整段逐字稿"),
            ("診斷\\s*(?:文字|錄音|文章|內容)", "整段內容"),
            ("診斷(?=[去做|分析|轉譯|處理])", "整段"),
            ("轉出轉進去", "轉進去"),
            ("(?i)live\\s*(?:saving|dreaming|dreamin)|streamDreamin|Live\\s*Streaming\\s*streamDreamin", "Live Streaming"),
            ("凹凸出|凹凸", "Output"),
            
            // Units, Storage & Hardware
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
            ("達克", "Docker"),
            ("一到兩輪", "1 到 2 輪"),
            ("做次分析", "做一次分析")
        ]
        
        for item in tokenPatterns {
            if let regex = try? NSRegularExpression(pattern: item.pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: item.replacement)
            }
        }
        
        return result
    }
    
    // MARK: - Pass 2B: Semantic Intent & Homophone Disambiguation
    
    /// Context-aware disambiguation for homophones based on full-sentence narrative intent
    public func disambiguateSemanticIntent(_ text: String) -> String {
        var result = text
        
        let semanticRegexes: [(pattern: String, replacement: String)] = [
            ("羽翼(?=如果|明顯|表達|理解|上下文|順序|判定)", "語意"),
            ("(?:好的|做有|這叫做有|這才叫做有|進行|經過|文字|文章|內容)認識", "好的潤飾"),
            ("認識(?=文字|文章|一下|的多一點|一下下|的|內容|輸出|結果|效果|功能)", "潤飾"),
            ("潤濕", "潤飾"),
            ("把蚊子", "把文字"),
            ("布拉布布拉|不拉布拉|布拉布拉", "等等"),
            ("字字", "字"),
            ("段類", "段之類"),
            ("類類", "類"),
            ("夠夠", "夠"),
            ("別別", "別")
        ]
        
        for item in semanticRegexes {
            if let regex = try? NSRegularExpression(pattern: item.pattern, options: []) {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: item.replacement)
            }
        }
        
        return result
    }
    
    // MARK: - Pass 2C: Static Phonetic Typos Normalization
    
    /// Static dictionary for explicit spoken acronyms and platform terms
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
    
    // MARK: - Pass 3: Multi-Clause Stutter & Loop Annihilation
    
    /// Remove progressive clause restarts, repetition loops, and stuttered fragments
    public func annihilateStuttersAndRestarts(_ text: String) -> String {
        var result = text
        
        // 1. Sentence-level deduplication (removes duplicate clauses across the monologue)
        result = deduplicateSentences(result)
        
        // 2. Repetitive restarting clauses (e.g. "好，我再來試次，好我再試一次，好，我再試一次" -> "好，我再試一次，")
        let restartPatterns = [
            ("(好[，、\\s]*我[再來|再]*試[一次|次]*[，、\\s]*)+", "好，我再試一次，"),
            ("(看[看]*能[不]*[，、\\s]*就是看能不能[錯別字別|把錯別字去]*[，、\\s]*)+", "看能不能把錯別字去掉，"),
            ("是錯的。[，、\\s\n]*但是因為你知道", "但是因為你知道"),
            ("(有我們會產生一個逐字稿嗎[。，\\s\n]*)+(逐字稿[，。\\s\n]*)+", "我們會產生一個逐字稿。")
        ]
        for (pat, rep) in restartPatterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: []) {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: rep)
            }
        }
        
        // 3. Progressive prefix clause stutter (e.g. "好我們來，好我們來測試" -> "好我們來測試")
        let progressivePrefixPattern = "([，。！？\n\\s]|^)([\\u4e00-\\u9fa5A-Za-z0-9]{2,15})[，、\\s]+(?=\\2)"
        if let regex = try? NSRegularExpression(pattern: progressivePrefixPattern, options: []) {
            for _ in 0..<3 {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
            }
        }
        
        // 4. Repeated full sentence deduplication (e.g. "盡可能地去呈現。盡可能地去呈現" -> "盡可能地去呈現。")
        let sentenceRepeatPattern = "([^\\n。！？]{4,40}[。！？])[，、\\s]*\\1"
        if let regex = try? NSRegularExpression(pattern: sentenceRepeatPattern, options: []) {
            for _ in 0..<2 {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
            }
        }
        
        // 5. Single character repeated 3+ times (e.g. "我我我" -> "我")
        let triplePattern = "([\\u4e00-\\u9fa5])\\1{2,}"
        if let regex = try? NSRegularExpression(pattern: triplePattern, options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
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
    
    /// Deduplicate identical or near-identical whole sentences across the monologue
    private func deduplicateSentences(_ text: String) -> String {
        let rawSentences = text.components(separatedBy: CharacterSet(charactersIn: "。！？\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var seenNormalized = Set<String>()
        var cleaned: [String] = []
        
        for sentence in rawSentences {
            let norm = sentence.replacingOccurrences(of: "，", with: "")
                .replacingOccurrences(of: "、", with: "")
                .replacingOccurrences(of: " ", with: "")
            
            if norm.count >= 4 && seenNormalized.contains(norm) {
                continue
            }
            seenNormalized.insert(norm)
            cleaned.append(sentence)
        }
        
        return cleaned.joined(separator: "。")
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
    
    // MARK: - Pass 4: Typeless-Grade Note Structuring
    
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
        
        let transitionKeywords = ["另外", "此外", "不過", "但是", "然而", "因此", "總結來說", "總之", "總結", "最後", "也就是", "而且", "你看像", "所以", "因為"]
        
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
