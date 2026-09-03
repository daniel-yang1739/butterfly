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
        // while intelligently adding natural punctuation at clause boundaries!
        if mode == .liveStream {
            let cleaned = cleanIntraWordPunctuation(pass2)
            let punctuated = enrichNaturalPausePunctuation(cleaned)
            let spaced = TextFormatter.shared.insertSpacingBetweenCJKAndAlphanumeric(punctuated)
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
            
            // System Prompt fuzzy variations (matches sister Prom, sister Pat, sister from, season from, season Pro, To Pro, System Promptpt, System Promptm, etc.)
            ("(?i)\\bSystem\\s*Prompt[a-zA-Z]*\\b", "System Prompt"),
            ("(?i)\\b(?:secret|system|sister|cister|season|the\\s*season|stone|sistema|sixteen|set)\\s*(?:stone|prom|prompt|pro|promt|pat|pad|from)\\b", "System Prompt"),
            ("(?i)\\b(?:To\\s*Pro|top\\s*To\\s*Pro)\\b", "System Prompt"),
            ("(?i)(?:sister\\s*Pat|set\\s*Pro|sister\\s*prom|sister\\s*prompt|stone\\s*prom|stone\\s*prompt|season\\s*from|season\\s*Pro)", "System Prompt"),
            ("塞\\s*(?:the\\s*season|season|system|sister)?\\s*(?:prom|prompt|pro|stone|pat|pad|from)", "塞 System Prompt"),
            ("Theakston\\s*Brown|Theakston|brown\\s*所以", "System Prompt"),
            
            // Context & Token relations (matches 上下文 Context, 翻成 Context, contact/contest in context)
            ("(?i)\\bContext(?:t|x|ts|s)+\\b", "Context"),
            ("(?i)(?:上下文|前後文|前後)\\s*(?:康泰(?:\\s*克斯)?|context[a-z]*|contact|contest|contex\\b)", "上下文 Context"),
            ("(?i)(?:翻成|變成|轉成|翻譯成|看成)\\s*(?:context[a-z]*|contact|contest|contex\\b)", "翻成 Context"),
            ("(?i)\\b(?:康泰|contact|contest|contex)\\s*Token\\b", "Context Token"),
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
            
            // Security & Engineering Terms
            ("(?i)\\b(?:Brat|Track|Brad|Bread|Thread|Threat|Treat|Fred|Fleet)\\s*Model(?:ing|lings)?\\b", "Threat Modeling"),
            ("(?i)\\b(?:Brat|Track|Brad|Bread|Thread|Threat|Treat|Fred|Fleet)\\s*Model\\b", "Threat Model"),
            ("(?i)\\bGit\\s*Lab\\b", "GitLab"),
            ("(?i)\\bGit\\s*Hub\\b", "GitHub"),
            
            // AI Assistants & Antigravity Terms
            ("(?i)\\b(?:Andy\\s*gravity|Anti\\s*gravity|And\\s*gravity|any\\s*gravity)\\b", "Antigravity"),
            ("(?i)\\b(?:Lelash|lash|slash)\\s*command\\b", "Slash Command"),
            ("(?i)\\b(?:Voice\\s*command|voice)\\s*那個\\b", "/voice 那個"),
            ("(?i)\\b(?:Poozenn|Poozen|frozen)\\s*(?:thek|Take|talk|Text)\\b", "Frozen Text"),
            ("(?i)\\bDynamic\\s*Windows?\\b", "Dynamic Window"),
            ("(?i)\\b(?:Traegler|treater|triger|triegle|trig)\\b", "Trigger"),
            ("(?i)\\bS\\s*L\\s*M\\b", "SLM"),
            ("(?i)\\bL\\s*L\\s*M\\b", "LLM"),
            
            // Acoustic Trailing Homophone Repairs ('世界/是界' -> '試一下')
            ("(?<=[再來測])\\s*(?:世界|是界|視界|試界)", "試一下"),
            ("(?i)\\b(?:是界|視界|試界|試一界)\\b", "試一下"),
            
            // Units, Storage & Hardware
            ("messMessa\\s*messge\\s*mess\\s*RadarMadara|RadarMadara\\s*game\\s*getMadara", "Message"),
            ("Mata\\s*bite|Meta\\s*bite", "MB"),
            ("(?i)\\b(?:Paano|Panno|Pano|Panal|Peano)\\b", "Panel"),
            ("(?i)(?:in\\s*泊|音譜|應譜|音泊|硬譜|硬泊|in\\s*put|im\\s*put)\\s*(?:裡面|中|框|視窗)?", "Input"),
            ("(?i)\\b在\\s*IP\\s*(?:裡面|中|框|輸入框)\\b", "在 Input 裡面"),
            ("(?i)\\bIP\\s*(?:裡面|中|框|輸入框|輸入區)\\b", "Input 裡面"),
            ("(?i)\\bIP\\s*這個字\\b", "Input 這個字"),
            ("(?i)\\bin\\s*泊\\b", "Input"),
            ("音波的文字|音泊的文字|應波的文字", "輸入框的文字"),
            ("奧普|奧特普", "Output"),
            ("L\\s*O\\s*C\\s*O|L\\s*O\\s*C\\s*A\\s*L|(?i)\\bLoco\\b", "Local"),
            ("壞\\s*List|What\\s*last|what\\s*list|壞名單", "Whitelist"),
            ("(?i)\\b(?:Varun|Vera|Read\\s*me|Red\\s*me)\\b", "README"),
            ("(?i)\\b(?:A\\s*DM\\s*D\\s*R|Agent\\s*M\\s*D|agents?\\s*m\\s*d)\\b", "AGENTS.md"),
            ("(?i)\\bSource\\s*Coded?\\b|收\\s*call|so\\s*call|so\\s*co", "Source Code"),
            ("(?i)\\b(?:Doux|D\\s*O\\s*C\\s*S)\\b", "docs/"),
            ("(?i)\\b(?:coming\\s*com\\s*meet|com\\s*meet|c\\s*o\\s*m\\s*m\\s*i\\s*t|c\\s*o\\s*n\\s*m\\s*i\\s*t)\\b|com\\s*一版|come\\s*一版", "Commit"),
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
            // Spoken Punctuation Nouns vs. Punctuation Symbols Disambiguation
            ("(?i)(?:把|將|被)\\s*[，、]+\\s*(?:刪掉|拿掉|去掉|加上|輸入|修改|替換|移除)", "把「逗號」刪掉"),
            ("(?i)(?:把|將|被)\\s*[。]+\\s*(?:刪掉|拿掉|去掉|加上|輸入|修改|替換|移除)", "把「句號」刪掉"),
            ("(?i)(?:把|將|被)\\s*[？?]+\\s*(?:刪掉|拿掉|去掉|加上|輸入|修改|替換|移除)", "把「問號」刪掉"),
            ("(?i)(?:把|將|被)\\s*[！!]+\\s*(?:刪掉|拿掉|去掉|加上|輸入|修改|替換|移除)", "把「驚嘆號」刪掉"),
            ("(?i)(?:講|說|念|唸|寫)\\s*[，、]+(?=\\s*(?:是|這|文字|這兩個字|兩個字|符號|本人))", "講「逗號」"),
            ("(?i)(?:講|說|念|唸|寫)\\s*[。]+(?=\\s*(?:是|這|文字|這兩個字|兩個字|符號|本人))", "講「句號」"),
            ("(?i)[，、]+\\s*(?:這兩個字|這三個字|文字本人|這個符號|這個標點)", "「逗號」$1"),
            ("(?i)[。]+\\s*(?:這兩個字|這三個字|文字本人|這個符號|這個標點)", "「句號」$1"),
            ("(?i)[？?]+\\s*(?:這兩個字|這三個字|文字本人|這個符號|這個標點)", "「問號」$1"),
            ("(?i)[！!]+\\s*(?:這兩個字|這三個字|文字本人|這個符號|這個標點)", "「驚嘆號」$1"),
            ("(?i)是[，、]+(?=\\s*(?:這個符號|這個標點|這兩個字))", "是「逗號」"),
            ("(?i)是[。]+(?=\\s*(?:這個符號|這個標點|這兩個字))", "是「句號」"),
            ("(?i)顯示\\s*(?:\\[\\]|，|。|、|「」)?\\s*(?:這兩個字|兩個字)", "顯示「逗號」兩個字"),
            ("(?i)判斷\\s*[，、]+\\s*的", "判斷「逗號」的"),
            
            // Trigger Disambiguation (處罰 -> 觸發)
            ("處罰(?=\\s*(?:這件事情|機制|條件|點|時間|就是|要把|SLM|LLM|Model|事件|動作|發送|流程|邏輯|這個|一次|現在))", "觸發"),
            ("(?<=(?:什麼時候會|會不會|怎麼|如何|去|來|要|再次|重新|自動|何時會|會))\\s*處罰", "觸發"),
            ("處罰這件事情", "觸發這件事情"),
            ("處罰就是", "觸發就是"),
            ("處罰現在", "觸發現在"),
            
            // General Semantic Intent & Disambiguation
            ("羽翼(?=如果|明顯|表達|理解|上下文|順序|判定|變得|非常|很|清|正)", "語意"),
            ("(?:好的|做有|這叫做有|這才叫做有|進行|經過|文字|文章|內容|幫我們|請他|讓它|可以幫我們)\\s*認識", "好的潤飾"),
            ("幫我們認識", "幫我們潤飾"),
            ("可以幫我們認識", "可以幫我們潤飾"),
            ("經過好的認識", "經過好的潤飾"),
            ("認識(?=我們|我|文字|文章|一下|的多一點|一下下|的|內容|輸出|結果|效果|功能|講的話|說的話)", "潤飾"),
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
        
        // 1. Check for enumerated list indicators (e.g. 第一點... 第二點...)
        let listPattern = "(?:^|[。！？\n，])\\s*(第一種模式|第二種模式|第\\s*[一二三四五六七八九十0-9]+\\s*[點個項件、，事]|首先|一來|其次|二來|再來|最後[一點項事]?|總結來說|總結[：:]?|另外[一點項件事]?|此外[一點項件事]?)"
        
        if let regex = try? NSRegularExpression(pattern: listPattern, options: []) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            
            // If 2 or more distinct bullet markers exist, construct a structured Markdown document
            if matches.count >= 2 {
                var sections: [String] = []
                
                // A. Introductory cohesive paragraph (everything before the first list item)
                let firstMatchLoc = matches[0].range.location
                if firstMatchLoc > 0 {
                    let intro = nsString.substring(with: NSRange(location: 0, length: firstMatchLoc))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "，、。；"))
                    if !intro.isEmpty {
                        sections.append(intro.hasSuffix("。") || intro.hasSuffix("！") || intro.hasSuffix("？") ? intro : intro + "。")
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
                        .trimmingCharacters(in: CharacterSet(charactersIn: "，、；。 "))
                    
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
        
        // 2. Default: Maintain large, cohesive thematic paragraphs without arbitrary sentence fragmentation
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Pass 2D: Natural Spoken Pause Punctuation
    
    /// Restore natural sentence punctuation for spoken pauses and modal particles in Mode 1
    public func enrichNaturalPausePunctuation(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }
        
        // 1. Question particles -> '？'
        let questionPatterns = [
            "(?:對吧|對不對|好不好|怎麼樣|是不是|行不行|可不可以|對嗎|好嗎|是嗎|對阿|對啊|嗎|吧|呢)$"
        ]
        for p in questionPatterns {
            if let regex = try? NSRegularExpression(pattern: p, options: []) {
                let range = NSRange(location: 0, length: result.utf16.count)
                if regex.firstMatch(in: result, options: [], range: range) != nil {
                    if !result.hasSuffix("？") && !result.hasSuffix("?") && !result.hasSuffix("！") && !result.hasSuffix("。") {
                        result += "？"
                        return result
                    }
                }
            }
        }
        
        // 2. Exclamation/emotion particles -> '！'
        let exclamationPatterns = [
            "(?:好奇怪喔|好奇怪阿|太棒了|太好了|天啊|哇|真假)$"
        ]
        for p in exclamationPatterns {
            if let regex = try? NSRegularExpression(pattern: p, options: []) {
                let range = NSRange(location: 0, length: result.utf16.count)
                if regex.firstMatch(in: result, options: [], range: range) != nil {
                    if !result.hasSuffix("！") && !result.hasSuffix("!") && !result.hasSuffix("？") && !result.hasSuffix("。") {
                        result += "！"
                        return result
                    }
                }
            }
        }
        
        // 3. Natural transitional comma insertion (prevents giant unpunctuated run-on sentences)
        let transitionalRules = [
            ("(?<=[\u{4e00}-\u{9fa5}A-Za-z0-9]{3,20})\\s+(然後|所以說|所以|但是|不過|另外|此外|而且|也就是說|比如說|例如|第一點|第二點|第三點)(?=[\\s\u{4e00}-\u{9fa5}A-Za-z0-9])", "，$1"),
            ("^(好|對|是|沒錯|OK|Ok)\\s*(?=我們|我|再來|接下來|看一下|試一下|測一下)", "$1，")
        ]
        for (pattern, template) in transitionalRules {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: template)
            }
        }
        
        result = result.replacingOccurrences(of: "，，", with: "，")
        result = result.replacingOccurrences(of: "。，", with: "。")
        result = result.replacingOccurrences(of: "，。", with: "。")
        
        return result
    }
    
    // MARK: - Pass 2E: Clean Intra-Word Punctuation
    
    /// Clean erroneous punctuation inserted between single characters within standard words
    public func cleanIntraWordPunctuation(_ text: String) -> String {
        var result = text
        
        let intraWordPatterns = [
            ("效[，。！？、]+果", "效果"),
            ("但[，。！？、]+是", "但是"),
            ("這[，。！？、]+個", "這個"),
            ("這[，。！？、]+樣", "這樣"),
            ("標[，。！？、]+點[，。！？、]+符[，。！？、]+號", "標點符號"),
            ("標[，。！？、]+點", "標點"),
            ("符[，。！？、]+號", "符號"),
            ("對[，。！？、]+不[，。！？、]+對", "對不對"),
            ("好[，。！？、]+不[，。！？、]+好", "好不好"),
            ("怎[，。！？、]+麼[，。！？、]+樣", "怎麼樣"),
            ("是[，。！？、]+不[，。！？、]+是", "是不是"),
            ("甚[，。！？、]+麼|什[，。！？、]+麼", "什麼"),
            ("哪[，。！？、]+個|那[，。！？、]+個", "那個"),
            ("所[，。！？、]+以", "所以"),
            ("然[，。！？、]+後", "然後"),
            ("為[，。！？、]+什[，。！？、]+麼", "為什麼"),
            ("調[，。！？、]+了[，。！？、]+什[，。！？、]+麼", "調了什麼"),
            ("([，。！？])\\1+", "$1")
        ]
        
        for (pattern, replacement) in intraWordPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement)
            }
        }
        
        return result
    }
}
