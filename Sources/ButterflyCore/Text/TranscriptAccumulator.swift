import Foundation

/// Robust monotonic transcript accumulator across pauses and ASR window resets
public final class TranscriptAccumulator: @unchecked Sendable {
    public static let shared = TranscriptAccumulator()
    
    private let lock = NSLock()
    public private(set) var fullText: String = ""
    private var lastUtterance: String = ""
    private var committedSlidingText: String = ""
    private var activeSlidingWindow: String = ""
    private var slidingWindowStart: Int?
    private var slidingWindowEnd: Int?
    
    public init() {}
    
    /// Reset accumulator state for a new recording session
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        fullText = ""
        lastUtterance = ""
        committedSlidingText = ""
        activeSlidingWindow = ""
        slidingWindowStart = nil
        slidingWindowEnd = nil
    }

    /// Merge a timestamped ASR window while keeping earlier text immutable.
    public func appendSlidingWindow(rawText: String, windowStartSample: Int, windowEndSample: Int? = nil) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return getFullText() }

        lock.lock()
        defer { lock.unlock() }

        let previousWindowEnd = slidingWindowEnd
        defer { slidingWindowEnd = windowEndSample }

        guard let previousWindowStart = slidingWindowStart else {
            slidingWindowStart = windowStartSample
            activeSlidingWindow = trimmed
            fullText = trimmed
            return fullText
        }

        if windowStartSample <= previousWindowStart {
            activeSlidingWindow = trimmed
            fullText = committedSlidingText + activeSlidingWindow
            return fullText
        }

        let oldCharacters = Array(activeSlidingWindow)
        let newCharacters = Array(trimmed)
        let windowsOverlap = previousWindowEnd.map { windowStartSample < $0 } ?? true
        if windowsOverlap, let alignment = Self.bestAlignment(old: oldCharacters, new: newCharacters) {
            committedSlidingText += String(oldCharacters[..<alignment.oldStart])
        } else {
            committedSlidingText += activeSlidingWindow
            if Self.needsSeparator(between: committedSlidingText, and: trimmed) {
                committedSlidingText += "，"
            }
        }

        slidingWindowStart = windowStartSample
        activeSlidingWindow = trimmed
        fullText = committedSlidingText + activeSlidingWindow
        return fullText
    }
    
    /// Process incremental transcript update from speech recognizer
    public func append(rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return getFullText() }
        
        lock.lock()
        defer { lock.unlock() }
        
        if lastUtterance.isEmpty {
            lastUtterance = trimmed
            fullText = trimmed
            return fullText
        }
        
        guard trimmed != lastUtterance else { return fullText }
        
        // 1. Direct forward append (fast path)
        if trimmed.hasPrefix(lastUtterance) {
            let suffixIndex = trimmed.index(trimmed.startIndex, offsetBy: lastUtterance.count)
            let delta = String(trimmed[suffixIndex...])
            fullText += delta
            lastUtterance = trimmed
            return fullText
        }
        
        // 2. Common prefix calculation
        let oldChars = Array(lastUtterance)
        let newChars = Array(trimmed)
        var common = 0
        let minLen = min(oldChars.count, newChars.count)
        while common < minLen && oldChars[common] == newChars[common] {
            common += 1
        }

        // 3. Replace the active window when Whisper revises more than a few
        // characters while preserving the already committed prefix.
        if common >= 2 && fullText.hasSuffix(lastUtterance) {
            fullText.removeLast(lastUtterance.count)
            fullText += trimmed
            lastUtterance = trimmed
            return fullText
        }

        // 4. Merge the overlap when whisper-stream advances its sliding window.
        let maximumOverlap = min(oldChars.count, newChars.count)
        if maximumOverlap >= 2 {
            for overlap in stride(from: maximumOverlap, through: 2, by: -1) {
                if oldChars.suffix(overlap).elementsEqual(newChars.prefix(overlap)) {
                    fullText += String(newChars.dropFirst(overlap))
                    lastUtterance = trimmed
                    return fullText
                }
            }
        }

        // 5. Pause boundary detection (New sentence started after speech pause)
        if common <= 1 && oldChars.count >= 4 {
            let punctuationSet: Set<Character> = ["。", "，", "！", "？", "；", "…", ".", ",", "!", "?", ";", " "]
            if let lastChar = fullText.last, !punctuationSet.contains(lastChar) {
                if lastUtterance.hasSuffix("嗎") || lastUtterance.hasSuffix("呢") || lastUtterance.hasSuffix("吧") || lastUtterance.hasSuffix("是不是") {
                    fullText += "？"
                } else {
                    fullText += "，"
                }
            }
            fullText += trimmed
            lastUtterance = trimmed
            return fullText
        }
        
        // 6. In-place word correction (Minor tail revisions <= 4 characters)
        let backspaceCount = oldChars.count - common
        if backspaceCount <= 4 {
            let toRemove = backspaceCount
            if fullText.count >= toRemove {
                fullText.removeLast(toRemove)
            }
            let suffixIndex = trimmed.index(trimmed.startIndex, offsetBy: common)
            fullText += String(trimmed[suffixIndex...])
            lastUtterance = trimmed
            return fullText
        }
        
        // 7. Large sliding window revision: Append only extra new tail characters
        if newChars.count > oldChars.count {
            let suffixIndex = trimmed.index(trimmed.startIndex, offsetBy: common)
            let delta = String(trimmed[suffixIndex...])
            fullText += delta
            lastUtterance = trimmed
        } else {
            // Keep existing accumulated history intact
            lastUtterance = trimmed
        }
        
        return fullText
    }
    
    /// Get the complete accumulated text across all utterances
    public func getFullText() -> String {
        lock.lock()
        defer { lock.unlock() }
        return fullText
    }

    private struct Alignment {
        let oldStart: Int
    }

    /// Match only the old suffix to the new prefix. Interior matches can replay
    /// the new prefix or erase unrelated speech that follows a shared word.
    private static func bestAlignment(old: [Character], new: [Character]) -> Alignment? {
        let oldNormalized = normalizedCharacters(old)
        let newNormalized = normalizedCharacters(new)
        let normalizedOverlap = min(oldNormalized.count, newNormalized.count)
        // Require stronger evidence when ignoring formatting differences.
        if normalizedOverlap >= 4 {
            for length in stride(from: normalizedOverlap, through: 4, by: -1) {
                let oldSuffix = oldNormalized.suffix(length)
                let newPrefix = newNormalized.prefix(length)
                if oldSuffix.map(\.value).elementsEqual(newPrefix.map(\.value)) {
                    return Alignment(oldStart: oldSuffix.first!.originalIndex)
                }
            }
        }

        let maximumOverlap = min(old.count, new.count)
        if maximumOverlap >= 2 {
            for length in stride(from: maximumOverlap, through: 2, by: -1) {
                let suffix = old.suffix(length)
                if suffix.elementsEqual(new.prefix(length)),
                   suffix.contains(where: { character in
                       character.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
                   }) {
                    return Alignment(oldStart: old.count - length)
                }
            }
        }
        return nil
    }

    private struct NormalizedCharacter {
        let value: Character
        let originalIndex: Int
    }

    private static func normalizedCharacters(_ characters: [Character]) -> [NormalizedCharacter] {
        // Keep technical punctuation such as C++, C#, paths, and version dots.
        let ignored = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",!?;:，。！？；：、"))
        return characters.enumerated().flatMap { index, character -> [NormalizedCharacter] in
            if character == ".", index + 1 == characters.count || characters[index + 1].isWhitespace {
                return []
            }
            guard !character.unicodeScalars.allSatisfy({ ignored.contains($0) }) else { return [] }
            return character.lowercased().map { NormalizedCharacter(value: $0, originalIndex: index) }
        }
    }

    private static func needsSeparator(between prefix: String, and suffix: String) -> Bool {
        guard let last = prefix.last, let first = suffix.first else { return false }
        let punctuation: Set<Character> = ["。", "，", "！", "？", "；", "…", ".", ",", "!", "?", ";", " "]
        return !punctuation.contains(last) && !punctuation.contains(first)
    }
}
