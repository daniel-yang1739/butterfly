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

/// Thread-safe Strict Clause-Level Sliding Window Buffer (Zero Avalanche, True Prefix Immutability, Two-Tone Dynamic HUD)
public final class SlidingWindowBuffer: @unchecked Sendable {
    private let lock = NSLock()
    
    /// Exact cumulative text that has physically been typed into the active OS cursor
    public private(set) var injectedCumulativeText: String = ""
    
    /// Confirmed historical text permanently locked and rendered in Bright White
    public private(set) var frozenText: String = ""
    
    /// Flag to guarantee strictly serialized, non-overlapping refinement passes
    private var isPolishingActive: Bool = false
    
    /// Active unfrozen text currently being spoken (rendered in Subtle Gray)
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
    
    // MARK: - Phase 1: Continuous Acoustic Streaming (Append-Only Fast Path + Clause Auto-Freeze)
    
    /// Process incoming real-time acoustic text from ASR stream while user is speaking
    public func appendStreamingText(_ rawFullText: String) -> SlidingDeltaAction {
        lock.lock()
        defer { lock.unlock() }
        
        let trimmed = rawFullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .noChange }
        
        // Mode 1: Convert to Taiwan Traditional Chinese
        let normalized = OpenCCTranslator.shared.convert(trimmed)
        
        // 1. Direct forward append fast-path (Append-Only, 0 Backspaces)
        if normalized.hasPrefix(injectedCumulativeText) {
            let suffixIndex = normalized.index(normalized.startIndex, offsetBy: injectedCumulativeText.count)
            let delta = String(normalized[suffixIndex...])
            if !delta.isEmpty {
                injectedCumulativeText = normalized
                autoCommitCompletedClauses()
                return .append(text: delta)
            }
            return .noChange
        }
        
        // 2. In-place tail refinement when ASR adjusts acoustic homophones at the active tail
        let (backspaces, replacement) = computeMinimalDelta(from: injectedCumulativeText, to: normalized)
        if backspaces <= maxBackspaceLimit {
            injectedCumulativeText = normalized
            autoCommitCompletedClauses()
            if backspaces == 0 && !replacement.isEmpty {
                return .append(text: replacement)
            } else if backspaces > 0 {
                return .replaceTail(backspaces: backspaces, replacement: replacement)
            }
        } else {
            // 3. Anti-freeze recovery: preserve screen text and append new suffix
            if normalized.count > injectedCumulativeText.count {
                let extraCount = normalized.count - injectedCumulativeText.count
                let newSuffix = String(normalized.suffix(extraCount))
                if !newSuffix.isEmpty {
                    injectedCumulativeText += newSuffix
                    autoCommitCompletedClauses()
                    return .append(text: newSuffix)
                }
            } else {
                injectedCumulativeText = normalized
                autoCommitCompletedClauses()
            }
        }
        
        return .noChange
    }
    
    // MARK: - Clause Auto-Freeze Helper
    
    /// Automatically advances `frozenText` when punctuation marks (，。？！；) are completed
    /// This immediately turns completed sentences into Bright White on the HUD while you continue speaking!
    private func autoCommitCompletedClauses() {
        // If current text has a punctuation mark that extends beyond frozenText
        let delimiters: [Character] = ["，", "。", "！", "？", "；", "…", "\n"]
        if let lastPunctuationIndex = injectedCumulativeText.lastIndex(where: { delimiters.contains($0) }) {
            let nextIndex = injectedCumulativeText.index(after: lastPunctuationIndex)
            let committedPrefix = String(injectedCumulativeText[..<nextIndex])
            if committedPrefix.count > frozenText.count {
                frozenText = committedPrefix
            }
        }
    }
    
    // MARK: - Phase 2: Serialized Pause-Gated Refinement (Strict 1-at-a-time Model Queue)
    
    /// Triggered when the speaker naturally pauses (e.g. 350ms silence)
    /// Refines ONLY the active unfrozen tail with domain vocabulary, Pangu spacing, numbers & units.
    /// Strictly serialized: Never touches or passes earlier frozen history to the model.
    public func onPauseTriggered() -> SlidingDeltaAction {
        lock.lock()
        defer { lock.unlock() }
        
        guard !injectedCumulativeText.isEmpty else { return .noChange }
        guard !isPolishingActive else { return .noChange }
        
        isPolishingActive = true
        defer { isPolishingActive = false }
        
        // 1. Extract ONLY the active unfrozen tail
        let tailToPolish: String
        if !frozenText.isEmpty && injectedCumulativeText.hasPrefix(frozenText) {
            let suffixIdx = injectedCumulativeText.index(injectedCumulativeText.startIndex, offsetBy: frozenText.count)
            tailToPolish = String(injectedCumulativeText[suffixIdx...])
        } else {
            tailToPolish = injectedCumulativeText
        }
        
        guard !tailToPolish.isEmpty else {
            frozenText = injectedCumulativeText
            return .noChange
        }
        
        // 2. Refine ONLY the active tail (domain tech terms, numbers, units, Pangu spacing)
        let refinedTail = TextPolisher.shared.polish(tailToPolish, mode: .liveStream)
        let targetFull = frozenText + refinedTail
        
        let (backspaces, replacement) = computeMinimalDelta(from: injectedCumulativeText, to: targetFull)
        
        if backspaces <= maxBackspaceLimit {
            injectedCumulativeText = targetFull
            frozenText = targetFull // Lock the finalized clause into frozen history
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
