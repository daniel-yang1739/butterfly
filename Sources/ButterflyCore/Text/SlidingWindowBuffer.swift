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

/// Thread-safe Cumulative Streaming & Serialized Pause-Gated Refiner (Zero Freeze & Zero Avalanche)
public final class SlidingWindowBuffer: @unchecked Sendable {
    private let lock = NSLock()
    
    /// Exact cumulative text that has physically been typed into the active OS cursor
    public private(set) var injectedCumulativeText: String = ""
    
    /// Confirmed historical text locked on pauses
    public private(set) var frozenText: String = ""
    
    /// Flag to guarantee strictly serialized, non-overlapping refinement passes
    private var isPolishingActive: Bool = false
    
    /// Active unfrozen text currently being spoken
    public var activeTail: String {
        guard !frozenText.isEmpty && injectedCumulativeText.hasPrefix(frozenText) else {
            return injectedCumulativeText
        }
        let suffixIdx = injectedCumulativeText.index(injectedCumulativeText.startIndex, offsetBy: frozenText.count)
        return String(injectedCumulativeText[suffixIdx...])
    }
    
    /// Maximum allowed backspaces in a single refinement to prevent screen jitter
    public let maxBackspaceLimit: Int
    
    public init(maxBackspaceLimit: Int = 25) {
        self.maxBackspaceLimit = maxBackspaceLimit
    }
    
    /// Reset the buffer for a new recording session
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        injectedCumulativeText = ""
        frozenText = ""
        isPolishingActive = false
    }
    
    /// Returns the complete transcribed text
    public var fullTranscript: String {
        lock.lock()
        defer { lock.unlock() }
        return injectedCumulativeText
    }
    
    // MARK: - Phase 1: Continuous Acoustic Streaming (Append-Only Fast Path)
    
    /// Process incoming real-time acoustic text from ASR stream while user is speaking
    public func appendStreamingText(_ rawFullText: String) -> SlidingDeltaAction {
        lock.lock()
        defer { lock.unlock() }
        
        let trimmed = rawFullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .noChange }
        
        // Mode 1: Convert to Taiwan Traditional Chinese and light tech formatting
        let normalized = OpenCCTranslator.shared.convert(trimmed)
        
        // 1. Direct forward append fast-path (Append-Only, 0 Backspaces)
        if normalized.hasPrefix(injectedCumulativeText) {
            let suffixIndex = normalized.index(normalized.startIndex, offsetBy: injectedCumulativeText.count)
            let delta = String(normalized[suffixIndex...])
            if !delta.isEmpty {
                injectedCumulativeText = normalized
                return .append(text: delta)
            }
            return .noChange
        }
        
        // 2. In-place tail refinement when ASR adjusts acoustic homophones at the tail
        let (backspaces, replacement) = computeMinimalDelta(from: injectedCumulativeText, to: normalized)
        if backspaces <= maxBackspaceLimit {
            injectedCumulativeText = normalized
            if backspaces == 0 && !replacement.isEmpty {
                return .append(text: replacement)
            } else if backspaces > 0 {
                return .replaceTail(backspaces: backspaces, replacement: replacement)
            }
        } else {
            // 3. CRITICAL ANTI-FREEZE RECOVERY:
            // If backspaces > maxBackspaceLimit (ASR modified text far in the past that was already frozen),
            // NEVER block or freeze typing! Keep the existing screen text intact, extract only newly appended suffix,
            // and continue streaming forward seamlessly!
            if normalized.count > injectedCumulativeText.count {
                let extraCount = normalized.count - injectedCumulativeText.count
                let newSuffix = String(normalized.suffix(extraCount))
                if !newSuffix.isEmpty {
                    injectedCumulativeText += newSuffix
                    return .append(text: newSuffix)
                }
            } else {
                // If length is the same or shorter, update internal state to stay synchronized
                injectedCumulativeText = normalized
            }
        }
        
        return .noChange
    }
    
    // MARK: - Phase 2: Serialized Pause-Gated Refinement (Strict 1-at-a-time Model Queue)
    
    /// Triggered when the speaker naturally pauses (e.g. 350ms silence)
    /// Refines the active text with domain vocabulary, Pangu spacing, numbers & units.
    /// Strictly serialized: Only allows ONE refinement pass at a time.
    public func onPauseTriggered() -> SlidingDeltaAction {
        lock.lock()
        defer { lock.unlock() }
        
        guard !injectedCumulativeText.isEmpty else { return .noChange }
        guard !isPolishingActive else { return .noChange }
        
        isPolishingActive = true
        defer { isPolishingActive = false }
        
        // Refine with Mode 1 live dictation polisher (Pangu spacing, numbers, tech terms like Context)
        let refined = TextPolisher.shared.polish(injectedCumulativeText, mode: .liveStream)
        
        let (backspaces, replacement) = computeMinimalDelta(from: injectedCumulativeText, to: refined)
        
        // Only apply if the change is within safe backspace limits
        if backspaces <= maxBackspaceLimit {
            injectedCumulativeText = refined
            frozenText = refined
            if backspaces == 0 && !replacement.isEmpty {
                return .append(text: replacement)
            } else if backspaces > 0 {
                return .replaceTail(backspaces: backspaces, replacement: replacement)
            }
        } else {
            frozenText = injectedCumulativeText
        }
        
        return .noChange
    }
    
    // MARK: - Helper Delta Computation
    
    /// Computes the minimal number of backspaces and replacement string needed to transform oldText to newText
    public func computeMinimalDelta(from oldText: String, to newText: String) -> (backspaces: Int, replacement: String) {
        let oldChars = Array(oldText)
        let newChars = Array(newText)
        
        var commonPrefixCount = 0
        let minLength = min(oldChars.count, newChars.count)
        
        while commonPrefixCount < minLength && oldChars[commonPrefixCount] == newChars[commonPrefixCount] {
            commonPrefixCount += 1
        }
        
        let oldPrefix = String(oldChars.prefix(commonPrefixCount))
        let oldUTF16 = oldText.utf16.count
        let oldPrefixUTF16 = oldPrefix.utf16.count
        let backspaces = max(0, oldUTF16 - oldPrefixUTF16)
        
        let replacement = String(newChars.dropFirst(commonPrefixCount))
        return (backspaces, replacement)
    }
}
