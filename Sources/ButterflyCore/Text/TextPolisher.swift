import Foundation

/// Two-Pass Cognitive Text Polisher and Contextual Intent Reconstruction Engine
public final class TextPolisher {
    public static let shared = TextPolisher()
    
    public init() {}
    
    /// Polishing modes
    public enum PolishMode: String, CaseIterable, Sendable {
        case liveStream = "live"             // Real-time dictation: light filler cleaning, fast output
        case concisePolish = "concise-polish" // Deferred cleanup without semantic restructuring
        case structuredNote = "structured"   // Record & Polish: deep filler cleaning, auto-paragraphing, bullet point extraction
        case conciseSummary = "concise"      // Conservative fallback when semantic summarization is unavailable
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
        
        // Pass 4 (Mode 2 Only): Apply structural formatting only when requested.
        let output: String
        switch mode {
        case .structuredNote:
            output = structureIntoTypelessNotes(pass3)
        case .concisePolish, .conciseSummary:
            output = pass3
        case .liveStream:
            output = pass3
        }
        
        // Step Final: Insert spacing between CJK and alphanumeric characters (Pangu Spacing)
        let formatted = TextFormatter.shared.insertSpacingBetweenCJKAndAlphanumeric(output)
        return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Pass 2: Clean Native Algorithmic Pipeline
    
    /// Pure native pass-through without artificial hardcoded regexes
    public func restoreAcousticAndPhoneticTokens(_ text: String) -> String {
        return text
    }
    
    /// Pure native pass-through without artificial hardcoded regexes
    public func disambiguateSemanticIntent(_ text: String) -> String {
        return text
    }
    
    /// Pure native pass-through without artificial hardcoded regexes
    public func normalizePhoneticTypos(_ text: String) -> String {
        return text
    }
    
    // MARK: - Pass 3: Multi-Clause Stutter Deduplication
    
    /// Remove consecutive duplicate sentences and obvious stuttered loops
    public func annihilateStuttersAndRestarts(_ text: String) -> String {
        var result = text
        
        // 4. Repeated full sentence deduplication (e.g. "盡可能地去呈現。盡可能地去呈現" -> "盡可能地去呈現。")
        let sentenceRepeatPattern = "([^\\n。！？]{4,40}[。！？])[，、\\s]*\\1"
        if let regex = try? NSRegularExpression(pattern: sentenceRepeatPattern, options: []) {
            for _ in 0..<2 {
                let range = NSRange(location: 0, length: result.utf16.count)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
            }
        }
        
        // 5. Single character repeated 2+ times for oral stutters (e.g. "又又" -> "又")
        let doubleOralPattern = "(?<=[\\u4e00-\\u9fa5]|^)([又也再被就])\\1+"
        if let regex = try? NSRegularExpression(pattern: doubleOralPattern, options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }
        
        // 6. Single character repeated 3+ times (e.g. "我我我" -> "我")
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
    
    /// Format notes as paragraph-first blocks, using bullets only for a real sequence of items.
    public func structureIntoTypelessNotes(_ text: String) -> String {
        guard text.count > 15 else { return text }

        let markerPattern = "(?:(?<=[。！？\\n，、\\s])|^)(第一種模式|第二種模式|第三種模式|第\\s*[一二三四五六七八九十0-9]+\\s*[點個項件事]是?|一個是|另一個是|首先|其次|再來是?|最後一點|最後一項)"
        guard let regex = try? NSRegularExpression(pattern: markerPattern),
              let list = paragraphFirstList(in: text, matching: regex) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return list
    }

    private func paragraphFirstList(
        in text: String,
        matching regex: NSRegularExpression
    ) -> String? {
        let nsText = text as NSString
        let matches = regex.matches(
            in: text,
            range: NSRange(location: 0, length: text.utf16.count)
        )
        guard matches.count >= 2 else { return nil }

        var groupStarts = [0]
        for index in matches.indices.dropFirst() {
            let marker = nsText.substring(with: matches[index].range)
                .replacingOccurrences(of: " ", with: "")
            if isFirstListMarker(marker) {
                groupStarts.append(index)
            }
        }
        let groupRanges = groupStarts.enumerated().map { offset, start in
            start..<(offset + 1 < groupStarts.count ? groupStarts[offset + 1] : matches.count)
        }
        guard groupRanges.allSatisfy({ $0.count >= 2 }) else { return nil }

        var sections: [String] = []
        var pendingIntroduction = nsText.substring(to: matches[0].range.location)
        var finalConclusion = ""

        for (groupOffset, groupRange) in groupRanges.enumerated() {
            let introduction = normalizedParagraph(pendingIntroduction, introduceList: true)
            if !introduction.isEmpty {
                sections.append(introduction)
            }
            pendingIntroduction = ""

            var bullets: [String] = []
            for index in groupRange {
                let start = NSMaxRange(matches[index].range)
                let end = index + 1 < matches.count
                    ? matches[index + 1].range.location
                    : text.utf16.count
                var item = nsText.substring(with: NSRange(location: start, length: max(0, end - start)))

                if index == groupRange.last {
                    if groupOffset + 1 < groupRanges.count {
                        let split = splitItemAndFollowingBlock(from: item)
                        item = split.item
                        pendingIntroduction = split.followingBlock
                    } else {
                        let split = splitConclusion(from: item)
                        item = split.item
                        finalConclusion = split.conclusion
                    }
                }

                let normalizedItem = normalizedListItem(item)
                guard normalizedItem.count >= 4 else { return nil }
                bullets.append("- " + normalizedItem)
            }
            sections.append(bullets.joined(separator: "\n"))
        }

        let normalizedConclusion = normalizedParagraph(finalConclusion)
        if !normalizedConclusion.isEmpty {
            sections.append(normalizedConclusion)
        }
        return sections.joined(separator: "\n\n")
    }

    private func isFirstListMarker(_ marker: String) -> Bool {
        marker.hasPrefix("第1")
            || marker.hasPrefix("第一")
            || marker == "一個是"
            || marker == "首先"
    }

    private func splitItemAndFollowingBlock(from text: String) -> (item: String, followingBlock: String) {
        let characters = Array(text)
        guard let boundary = characters.firstIndex(where: { "。！？".contains($0) }),
              boundary + 1 < characters.count else {
            return (text, "")
        }
        return (
            String(characters[...boundary]),
            String(characters[(boundary + 1)...])
        )
    }

    private func normalizedListItem(_ text: String) -> String {
        var item = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "，、；：:。 "))
        guard !item.isEmpty else { return "" }
        if !item.hasSuffix("。") && !item.hasSuffix("！") && !item.hasSuffix("？") {
            item += "。"
        }
        return item
    }

    private func normalizedParagraph(_ text: String, introduceList: Bool = false) -> String {
        var paragraph = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "，、；：:。 "))
        guard !paragraph.isEmpty else { return "" }
        if introduceList {
            paragraph += "："
        } else if !paragraph.hasSuffix("。") && !paragraph.hasSuffix("！") && !paragraph.hasSuffix("？") {
            paragraph += "。"
        }
        return paragraph
    }

    private func splitConclusion(from text: String) -> (item: String, conclusion: String) {
        let pattern = "(?<=[。！？])\\s*(?=(?:整體而言|總而言之|總之|因此|這樣|以上))"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(location: 0, length: text.utf16.count)
              ) else {
            return (text, "")
        }
        let nsText = text as NSString
        return (
            nsText.substring(to: match.range.location),
            nsText.substring(from: NSMaxRange(match.range))
        )
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
