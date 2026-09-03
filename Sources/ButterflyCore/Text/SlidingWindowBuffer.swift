import Foundation

/// Action to apply to the focused OS cursor to synchronize with the streaming buffer
public enum SlidingDeltaAction: Equatable, Sendable {
    /// Pure forward character append (0 backspaces)
    case append(text: String)
    /// In-place suffix replacement with minimal backspaces
    case replaceTail(backspaces: Int, replacement: String)
    /// No keystroke action needed
    case noChange
}

/// Thread-safe, Index-Based Sliding Window Buffer with Full Context Awareness
/// - Continuous speech: Streams forward smoothly in Active Gray without interruption
/// - 1.0s Silence pause: Feeds full context to Polisher, refines only the active tail, and commits to Frozen White.
public final class SlidingWindowBuffer: @unchecked Sendable {
    private let lock = NSLock()
    
    /// Single source of truth: Exact cumulative string physically typed on screen
    public private(set) var screenText: String = ""
    
    /// Character index demarcating Frozen Prefix (0..<frozenIndex) from Active Tail (frozenIndex...)
    public private(set) var frozenIndex: Int = 0
    
    /// Flag to guarantee strictly serialized refinement
    private var isPolishingActive: Bool = false
    
    /// Maximum allowed backspaces in a single active tail refinement
    public let maxBackspaceLimit: Int
    
    public init(maxBackspaceLimit: Int = 25) {
        self.maxBackspaceLimit = maxBackspaceLimit
    }
    
    /// Reset the buffer for a new recording session
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        screenText = ""
        frozenIndex = 0
        isPolishingActive = false
    }
    
    /// Returns the complete transcribed text
    public var fullTranscript: String {
        lock.lock()
        defer { lock.unlock() }
        return screenText
    }
    
    /// Historical confirmed text locked on 1.0s pauses (Rendered in Bright White)
    public var frozenText: String {
        lock.lock()
        defer { lock.unlock() }
        guard frozenIndex > 0 && frozenIndex <= screenText.count else { return "" }
        let idx = screenText.index(screenText.startIndex, offsetBy: frozenIndex)
        return String(screenText[..<idx])
    }
    
    /// Active text currently being spoken (Rendered in Subtle Gray)
    public var activeTail: String {
        lock.lock()
        defer { lock.unlock() }
        guard frozenIndex < screenText.count else { return "" }
        let idx = screenText.index(screenText.startIndex, offsetBy: frozenIndex)
        return String(screenText[idx...])
    }
    
    // MARK: - Phase 1: Continuous Acoustic Streaming (Append-Only Fast Path)
    
    /// Process incoming real-time acoustic text from ASR stream while user is speaking
    public func appendStreamingText(_ rawFullText: String) -> SlidingDeltaAction {
        lock.lock()
        defer { lock.unlock() }
        
        let trimmed = rawFullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .noChange }
        
        // Convert incoming acoustic text to Taiwan Traditional Chinese
        let normalized = OpenCCTranslator.shared.convert(trimmed)
        
        // 1. Direct forward append fast-path (Append-Only, 0 Backspaces)
        if normalized.hasPrefix(screenText) {
            let suffixIndex = normalized.index(normalized.startIndex, offsetBy: screenText.count)
            let delta = String(normalized[suffixIndex...])
            if !delta.isEmpty {
                screenText = normalized
                return .append(text: delta)
            }
            return .noChange
        }
        
        // 2. In-place tail adjustment when ASR revises phonetics at the active tail
        let (backspaces, replacement) = computeTailDelta(from: screenText, to: normalized, protectedLength: frozenIndex)
        if backspaces <= maxBackspaceLimit {
            screenText = normalized
            if backspaces == 0 && !replacement.isEmpty {
                return .append(text: replacement)
            } else if backspaces > 0 {
                return .replaceTail(backspaces: backspaces, replacement: replacement)
            }
        } else {
            // Anti-freeze safety: Clamp backspaces to protected boundary so earlier text is NEVER deleted or repeated!
            if normalized.count > screenText.count {
                let extraCount = normalized.count - screenText.count
                let newSuffix = String(normalized.suffix(extraCount))
                if !newSuffix.isEmpty {
                    screenText += newSuffix
                    return .append(text: newSuffix)
                }
            } else {
                screenText = normalized
            }
        }
        
        return .noChange
    }
    
    // MARK: - Phase 2: Serialized 1.0s Pause-Gated Refinement (Full Context Input -> Active Tail Output)
    
    /// Triggered when the speaker naturally pauses for >= 1.0 second.
    /// - Sends FULL text (`screenText`) to the Polisher for comprehensive context disambiguation.
    /// - Replaces ONLY the active tail (`screenText[frozenIndex...]`), leaving historical prefix 100% untouched.
    /// - Advances `frozenIndex` to lock the finalized segment into Bright White.
    public func onPauseTriggered() -> SlidingDeltaAction {
        lock.lock()
        defer { lock.unlock() }
        
        guard !screenText.isEmpty else { return .noChange }
        guard !isPolishingActive else { return .noChange }
        
        isPolishingActive = true
        defer { isPolishingActive = false }
        
        let splitIdx = screenText.index(screenText.startIndex, offsetBy: min(frozenIndex, screenText.count))
        let frozenPrefix = String(screenText[..<splitIdx])
        let activeTail = String(screenText[splitIdx...])
        
        guard !activeTail.isEmpty else {
            frozenIndex = screenText.count
            return .noChange
        }
        
        // 1. Pass FULL text to Polisher for global contextual awareness
        let refinedFull = TextPolisher.shared.polish(screenText, mode: .liveStream)
        
        // 2. Extract ONLY the polished tail after the frozen prefix boundary
        let refinedTail: String
        if refinedFull.count >= frozenPrefix.count && refinedFull.hasPrefix(frozenPrefix) {
            let tailIdx = refinedFull.index(refinedFull.startIndex, offsetBy: frozenPrefix.count)
            refinedTail = String(refinedFull[tailIdx...])
        } else {
            // Fallback: If model slightly formatted prefix, polish only the active tail to guarantee prefix immutability
            refinedTail = TextPolisher.shared.polish(activeTail, mode: .liveStream)
        }
        
        let targetFull = frozenPrefix + refinedTail
        guard targetFull != screenText else {
            frozenIndex = screenText.count
            return .noChange
        }
        
        let (backspaces, replacement) = computeTailDelta(from: screenText, to: targetFull, protectedLength: frozenIndex)
        
        if backspaces <= maxBackspaceLimit {
            screenText = targetFull
            frozenIndex = targetFull.count // Advance frozen checkpoint to current pause position
            if backspaces == 0 && !replacement.isEmpty {
                return .append(text: replacement)
            } else if backspaces > 0 {
                return .replaceTail(backspaces: backspaces, replacement: replacement)
            }
        } else {
            frozenIndex = screenText.count
        }
        
        return .noChange
    }
    
    // MARK: - Protected Delta Computation
    
    /// Computes delta between oldText and newText, ensuring we NEVER backspace past protectedLength
    public func computeTailDelta(from oldText: String, to newText: String, protectedLength: Int) -> (backspaces: Int, replacement: String) {
        let oldChars = Array(oldText)
        let newChars = Array(newText)
        
        var commonPrefixCount = 0
        let minLength = min(oldChars.count, newChars.count)
        
        while commonPrefixCount < minLength && oldChars[commonPrefixCount] == newChars[commonPrefixCount] {
            commonPrefixCount += 1
        }
        
        // Clamping: Never backspace past protected length
        let effectivePrefix = max(commonPrefixCount, min(protectedLength, oldChars.count))
        let backspaces = max(0, oldChars.count - effectivePrefix)
        let replacement = (effectivePrefix < newChars.count) ? String(newChars[effectivePrefix...]) : ""
        
        return (backspaces, replacement)
    }
}
