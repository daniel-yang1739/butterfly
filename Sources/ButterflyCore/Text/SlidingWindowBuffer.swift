import Foundation

/// Action to apply to the focused OS cursor to synchronize with the sliding window
public enum SlidingDeltaAction: Equatable, Sendable {
    /// Pure forward character append (0 backspaces)
    case append(text: String)
    /// In-place suffix replacement with minimal backspaces
    case replaceTail(backspaces: Int, replacement: String)
    /// No keystroke action needed
    case noChange
}

/// State snapshot of the SlidingWindowBuffer
public struct SlidingWindowSnapshot: Equatable, Sendable {
    public let frozenText: String
    public let activeTail: String
    public let injectedTail: String
    public var fullText: String {
        return frozenText + activeTail
    }
}

/// Core sliding window buffer managing Frozen Prefix and Active Tail refinement for Mode 1
public final class SlidingWindowBuffer: @unchecked Sendable {
    private let lock = NSLock()
    
    /// Permanently committed text (never modified or backspaced)
    public private(set) var frozenText: String = ""
    
    /// Active clause currently being spoken in the latest window
    public private(set) var activeTail: String = ""
    
    /// Text that has physically been typed into the OS active cursor for the current active clause
    public private(set) var injectedTail: String = ""
    
    /// Maximum allowed backspaces in a single refinement to prevent screen jitter
    public let maxBackspaceLimit: Int
    
    public init(maxBackspaceLimit: Int = 15) {
        self.maxBackspaceLimit = maxBackspaceLimit
    }
    
    /// Reset the buffer for a new recording session
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        frozenText = ""
        activeTail = ""
        injectedTail = ""
    }
    
    /// Returns the complete transcribed text (frozen + active)
    public var fullTranscript: String {
        lock.lock()
        defer { lock.unlock() }
        return frozenText + activeTail
    }
    
    /// Current state snapshot
    public var snapshot: SlidingWindowSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return SlidingWindowSnapshot(
            frozenText: frozenText,
            activeTail: activeTail,
            injectedTail: injectedTail
        )
    }
    
    // MARK: - Phase 1: Continuous Acoustic Streaming (Append-Only Fast Path)
    
    /// Process incoming real-time acoustic text from ASR stream while user is speaking
    public func appendStreamingText(_ rawFullText: String) -> SlidingDeltaAction {
        lock.lock()
        defer { lock.unlock() }
        
        let trimmedFull = rawFullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFull.isEmpty else { return .noChange }
        
        // 1. Extract the active tail by stripping the frozen prefix if present
        var newActiveTail = trimmedFull
        if !frozenText.isEmpty && trimmedFull.hasPrefix(frozenText) {
            let suffixIndex = trimmedFull.index(trimmedFull.startIndex, offsetBy: frozenText.count)
            newActiveTail = String(trimmedFull[suffixIndex...])
        }
        
        // Mode 1 Streaming: preserve acoustic tokens with basic Traditional Chinese conversion
        newActiveTail = OpenCCTranslator.shared.convert(newActiveTail)
        self.activeTail = newActiveTail
        
        // 2. Direct forward append fast-path (Append-Only)
        if newActiveTail.hasPrefix(injectedTail) {
            let suffixIndex = newActiveTail.index(newActiveTail.startIndex, offsetBy: injectedTail.count)
            let delta = String(newActiveTail[suffixIndex...])
            if !delta.isEmpty {
                injectedTail = newActiveTail
                return .append(text: delta)
            }
            return .noChange
        }
        
        // 3. Fallback: Calculate common prefix if acoustic model slightly revised active tail
        let (backspaces, replacement) = computeMinimalDelta(from: injectedTail, to: newActiveTail)
        if backspaces <= maxBackspaceLimit {
            injectedTail = newActiveTail
            if backspaces == 0 && !replacement.isEmpty {
                return .append(text: replacement)
            } else if backspaces > 0 {
                return .replaceTail(backspaces: backspaces, replacement: replacement)
            }
        }
        
        return .noChange
    }
    
    // MARK: - Phase 2: Pause-Gated Refinement (Triggered on ~350ms Silence)
    
    /// Triggered when the speaker naturally pauses (e.g. 350ms silence)
    /// Refines the active tail with domain vocabulary, Pangu spacing, numbers & units, then freezes the clause.
    public func onPauseTriggered() -> SlidingDeltaAction {
        lock.lock()
        defer { lock.unlock() }
        
        guard !activeTail.isEmpty else { return .noChange }
        
        // 1. Refine active tail with Mode 1 formatting (Pangu spacing, numbers, tech terms like Context)
        let refined = TextPolisher.shared.polish(activeTail, mode: .liveStream)
        
        // 2. Calculate minimum delta between what is typed in cursor and the refined text
        let (backspaces, replacement) = computeMinimalDelta(from: injectedTail, to: refined)
        
        // Update state: commit this clause into frozenText
        let finalClause = refined
        self.frozenText += finalClause
        self.activeTail = ""
        self.injectedTail = ""
        
        if backspaces == 0 && replacement.isEmpty {
            return .noChange
        } else if backspaces == 0 && !replacement.isEmpty {
            return .append(text: replacement)
        } else {
            return .replaceTail(backspaces: backspaces, replacement: replacement)
        }
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
