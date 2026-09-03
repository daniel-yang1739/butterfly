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

/// Prepared refinement plan for Two-Phase Commit cursor synchronization
public struct PreparedRefinement: Sendable {
    public let action: SlidingDeltaAction
    public let targetText: String
    public let newFrozenIndex: Int
    public let newPolishedIndex: Int
}

/// Thread-safe, Index-Based Sliding Window Buffer with Punctuation Conservation & Tri-Color 2PC
/// - Punctuation Conservation: Existing punctuation marks (，, 。, ！, ？, ；) are 100% STICKY and NEVER erased by ASR stream fluctuations!
/// - ⚪ White (0 ..< frozenIndex): Confirmed historical text (100% Locked & Immutable)
/// - 🟡 Amber Gold (frozenIndex ..< polishedIndex): AI Polished Dynamic Window (80% Depth, eligible for future refinement)
/// - 🔘 Subtle Gray (polishedIndex ..< screenText.count): Raw incoming speech currently being spoken
public final class SlidingWindowBuffer: @unchecked Sendable {
    private let lock = NSLock()
    
    /// Single source of truth: Exact cumulative string physically typed on screen
    public private(set) var screenText: String = ""
    
    /// Character index for ⚪ Locked White text (0..<frozenIndex)
    public private(set) var frozenIndex: Int = 0
    
    /// Character index for 🟡 AI Polished Amber Gold text (frozenIndex..<polishedIndex)
    public private(set) var polishedIndex: Int = 0
    
    /// Mutex flag ensuring keystroke injection and buffer mutation are atomic
    private var isCursorInjecting: Bool = false
    
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
        polishedIndex = 0
        isCursorInjecting = false
    }
    
    /// Finalize and lock the entire transcript when recording session concludes (All turns ⚪ White)
    public func finalizeAll() {
        lock.lock()
        defer { lock.unlock() }
        frozenIndex = screenText.count
        polishedIndex = screenText.count
        isCursorInjecting = false
    }
    
    /// Returns the complete transcribed text
    public var fullTranscript: String {
        lock.lock()
        defer { lock.unlock() }
        return screenText
    }
    
    /// ⚪ Tier 1: Historical confirmed text permanently locked (Rendered in Bright White)
    public var frozenText: String {
        lock.lock()
        defer { lock.unlock() }
        guard frozenIndex > 0 && frozenIndex <= screenText.count else { return "" }
        let idx = screenText.index(screenText.startIndex, offsetBy: min(frozenIndex, screenText.count))
        return String(screenText[..<idx])
    }
    
    /// 🟡 Tier 2: AI Polished segment in the active wave (Rendered in Amber Gold)
    public var polishedText: String {
        lock.lock()
        defer { lock.unlock() }
        guard polishedIndex > frozenIndex && polishedIndex <= screenText.count else { return "" }
        let start = screenText.index(screenText.startIndex, offsetBy: min(frozenIndex, screenText.count))
        let end = screenText.index(screenText.startIndex, offsetBy: min(polishedIndex, screenText.count))
        return String(screenText[start..<end])
    }
    
    /// 🔘 Tier 3: Raw incoming speech currently being spoken (Rendered in Subtle Gray)
    public var activeTail: String {
        lock.lock()
        defer { lock.unlock() }
        guard polishedIndex < screenText.count else { return "" }
        let idx = screenText.index(screenText.startIndex, offsetBy: min(polishedIndex, screenText.count))
        return String(screenText[idx...])
    }
    
    // MARK: - Phase 1: Continuous Acoustic Streaming with Sticky Punctuation Conservation
    
    /// Process incoming real-time acoustic text from ASR stream while user is speaking
    public func appendStreamingText(_ rawFullText: String) -> SlidingDeltaAction {
        lock.lock()
        defer { lock.unlock() }
        
        // If physical cursor is currently busy executing backspaces, defer to avoid race collision
        guard !isCursorInjecting else { return .noChange }
        
        let trimmed = rawFullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .noChange }
        
        // Convert incoming acoustic text to Taiwan Traditional Chinese
        let normalized = OpenCCTranslator.shared.convert(trimmed)
        
        // Punctuation Conservation Law: Re-inject established punctuation marks into normalized text
        // so raw ASR incoming speech NEVER erases question marks, commas, or periods!
        let preservedNormalized = preserveEstablishedPunctuation(from: screenText, to: normalized, protectedLength: frozenIndex)
        
        // 1. Direct forward append fast-path (Append-Only, 0 Backspaces)
        if preservedNormalized.hasPrefix(screenText) {
            let suffixIndex = preservedNormalized.index(preservedNormalized.startIndex, offsetBy: screenText.count)
            let delta = String(preservedNormalized[suffixIndex...])
            if !delta.isEmpty {
                screenText = preservedNormalized
                return .append(text: delta)
            }
            return .noChange
        }
        
        // 2. In-place tail adjustment when ASR revises phonetics at the active tail
        let (backspaces, replacement) = computeTailDelta(from: screenText, to: preservedNormalized, protectedLength: frozenIndex)
        if backspaces <= maxBackspaceLimit {
            screenText = preservedNormalized
            if backspaces == 0 && !replacement.isEmpty {
                return .append(text: replacement)
            } else if backspaces > 0 {
                return .replaceTail(backspaces: backspaces, replacement: replacement)
            }
        } else {
            // Anti-freeze safety: Clamp backspaces to protected boundary
            if preservedNormalized.count > screenText.count {
                let extraCount = preservedNormalized.count - screenText.count
                let newSuffix = String(preservedNormalized.suffix(extraCount))
                if !newSuffix.isEmpty {
                    screenText += newSuffix
                    return .append(text: newSuffix)
                }
            } else {
                screenText = preservedNormalized
            }
        }
        
        return .noChange
    }
    
    // MARK: - Phase 2: Tri-Color 20% Stride Dynamic Window Refinement (Two-Phase Commit)
    
    /// Step 1: Prepare refinement plan with 20% Stride / 80% Dynamic Overlap Window
    public func preparePauseRefinement() -> PreparedRefinement? {
        lock.lock()
        defer { lock.unlock() }
        
        guard !screenText.isEmpty && !isCursorInjecting else { return nil }
        
        let splitIdx = screenText.index(screenText.startIndex, offsetBy: min(frozenIndex, screenText.count))
        let frozenPrefix = String(screenText[..<splitIdx])
        let activeTail = String(screenText[splitIdx...])
        
        guard !activeTail.isEmpty else {
            frozenIndex = screenText.count
            polishedIndex = screenText.count
            return nil
        }
        
        // 1. Pass FULL text to Polisher for global contextual awareness
        let refinedFull = TextPolisher.shared.polish(screenText, mode: .liveStream)
        
        // 2. Extract ONLY the polished tail after the frozen prefix boundary
        let refinedTail: String
        if refinedFull.count >= frozenPrefix.count && refinedFull.hasPrefix(frozenPrefix) {
            let tailIdx = refinedFull.index(refinedFull.startIndex, offsetBy: frozenPrefix.count)
            refinedTail = String(refinedFull[tailIdx...])
        } else {
            refinedTail = TextPolisher.shared.polish(activeTail, mode: .liveStream)
        }
        
        let targetFull = frozenPrefix + refinedTail
        guard targetFull != screenText else {
            frozenIndex = min(polishedIndex, screenText.count)
            polishedIndex = screenText.count
            return nil
        }
        
        let (backspaces, replacement) = computeTailDelta(from: screenText, to: targetFull, protectedLength: frozenIndex)
        guard backspaces <= maxBackspaceLimit else {
            frozenIndex = screenText.count
            polishedIndex = screenText.count
            return nil
        }
        
        let action: SlidingDeltaAction
        if backspaces == 0 && !replacement.isEmpty {
            action = .append(text: replacement)
        } else if backspaces > 0 {
            action = .replaceTail(backspaces: backspaces, replacement: replacement)
        } else {
            action = .noChange
        }
        
        // 3. Mathematical 20% Stride / 80% Dynamic Overlap Progression:
        let previousFrozen = frozenIndex
        let activeSpan = targetFull.count - previousFrozen
        let newFrozenIndex: Int
        if activeSpan > 8 {
            let advanceStep = max(1, Int(Double(activeSpan) * 0.20))
            let rawTarget = previousFrozen + advanceStep
            var aligned = rawTarget
            let chars = Array(targetFull)
            let puncts: [Character] = ["，", "。", "！", "？", "；", "\n"]
            for offset in 0...min(6, Int(Double(activeSpan) * 0.35)) {
                let r = rawTarget + offset
                if r < chars.count && puncts.contains(chars[r]) {
                    aligned = r + 1
                    break
                }
                let l = rawTarget - offset
                if l > previousFrozen && puncts.contains(chars[l]) {
                    aligned = l + 1
                    break
                }
            }
            newFrozenIndex = max(previousFrozen, min(aligned, targetFull.count))
        } else {
            newFrozenIndex = previousFrozen
        }
        let newPolishedIndex = targetFull.count
        
        isCursorInjecting = true
        return PreparedRefinement(
            action: action,
            targetText: targetFull,
            newFrozenIndex: newFrozenIndex,
            newPolishedIndex: newPolishedIndex
        )
    }
    
    /// Step 2: Commit RAM pointers ONLY AFTER physical OS cursor keystrokes have finished executing
    public func commitPauseRefinement(_ prepared: PreparedRefinement) {
        lock.lock()
        defer { lock.unlock() }
        
        self.screenText = prepared.targetText
        self.frozenIndex = prepared.newFrozenIndex
        self.polishedIndex = prepared.newPolishedIndex
        self.isCursorInjecting = false
    }
    
    /// Cancel in-flight injection lock if an error occurred
    public func cancelPauseRefinement() {
        lock.lock()
        defer { lock.unlock() }
        self.isCursorInjecting = false
    }
    
    /// Legacy Compatibility Method for testing
    public func onPauseTriggered() -> SlidingDeltaAction {
        guard let prepared = preparePauseRefinement() else {
            return .noChange
        }
        commitPauseRefinement(prepared)
        return prepared.action
    }
    
    // MARK: - Punctuation Conservation Algorithm
    
    /// Re-injects established punctuation marks from oldText into newText
    /// so ASR's unpunctuated raw stream never deletes question marks, commas, or periods!
    public func preserveEstablishedPunctuation(from oldText: String, to newText: String, protectedLength: Int) -> String {
        let puncts: [Character] = ["，", "。", "！", "？", "；", "、"]
        let oldChars = Array(oldText)
        let newChars = Array(newText)
        
        var iOld = 0
        var iNew = 0
        var merged: [Character] = []
        
        while iOld < oldChars.count && iNew < newChars.count {
            if oldChars[iOld] == newChars[iNew] {
                merged.append(oldChars[iOld])
                iOld += 1
                iNew += 1
            } else if puncts.contains(oldChars[iOld]) && oldChars[iOld] != newChars[iNew] {
                // If oldText has a punctuation mark that newText omitted, preserve the punctuation!
                merged.append(oldChars[iOld])
                iOld += 1
            } else if puncts.contains(newChars[iNew]) {
                merged.append(newChars[iNew])
                iNew += 1
            } else {
                merged.append(newChars[iNew])
                iOld += 1
                iNew += 1
            }
        }
        
        while iOld < oldChars.count && puncts.contains(oldChars[iOld]) {
            merged.append(oldChars[iOld])
            iOld += 1
        }
        
        while iNew < newChars.count {
            merged.append(newChars[iNew])
            iNew += 1
        }
        
        return String(merged)
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
