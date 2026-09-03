import Foundation

/// Robust monotonic transcript accumulator across pauses and ASR window resets
public final class TranscriptAccumulator: @unchecked Sendable {
    public static let shared = TranscriptAccumulator()
    
    private let lock = NSLock()
    public private(set) var fullText: String = ""
    private var lastUtterance: String = ""
    
    public init() {}
    
    /// Reset accumulator state for a new recording session
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        fullText = ""
        lastUtterance = ""
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
        
        // 3. Pause boundary detection (New sentence started after speech pause)
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
        
        // 4. In-place word correction (Minor tail revisions <= 4 characters)
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
        
        // 5. Large sliding window revision: Append only extra new tail characters
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
}
