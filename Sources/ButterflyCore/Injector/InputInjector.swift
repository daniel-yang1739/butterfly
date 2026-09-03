import Foundation
#if os(macOS)
import AppKit
import ApplicationServices

/// Active window text injector and clipboard protection proxy
public final class InputInjector: @unchecked Sendable {
    public static let shared = InputInjector()
    
    public init() {}
    
    /// Inject a block of text into the active focused input using Cmd+V with clipboard preservation
    @discardableResult
    public func inject(text: String, restoreClipboard: Bool = true) async -> Bool {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return false }
        
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        
        // 1. Write clean text to pasteboard
        pasteboard.clearContents()
        pasteboard.setString(cleanText, forType: .string)
        
        // 2. Simulate Cmd + V paste keystroke
        simulatePasteCommand()
        
        // 3. Restore previous clipboard contents if requested
        if restoreClipboard, let original = previousString {
            try? await Task.sleep(nanoseconds: 80_000_000) // 80ms delay to ensure target app reads pasteboard
            pasteboard.clearContents()
            pasteboard.setString(original, forType: .string)
        }
        
        return true
    }
    
    /// Live incremental Unicode typing directly into cursor via CGEvent (without touching pasteboard)
    public func typeUnicodeString(_ string: String) {
        let utf16Chars = Array(string.utf16)
        guard !utf16Chars.isEmpty else { return }
        
        if let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
           let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
            eventDown.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
            eventDown.post(tap: .cghidEventTap)
            
            eventUp.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
            eventUp.post(tap: .cghidEventTap)
        }
    }
    
    /// Send backspace keystrokes to erase revised suffix reliably
    public func sendBackspaces(count: Int) {
        guard count > 0 else { return }
        let deleteKeyCode: CGKeyCode = 51 // macOS Delete / Backspace keycode
        
        for _ in 0..<count {
            if let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: deleteKeyCode, keyDown: true),
               let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: deleteKeyCode, keyDown: false) {
                eventDown.post(tap: .cghidEventTap)
                eventUp.post(tap: .cghidEventTap)
            }
            usleep(1200) // 1.2ms micro-delay to ensure target app event queues process every backspace reliably
        }
    }
    
    /// Utterance-Aware Real-time Live Stream Typing
    public func injectStreamingDelta(newText: String, previousText: inout String) {
        var currentNewText = newText
        if previousText.isEmpty {
            currentNewText = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard currentNewText != previousText else { return }
        
        // 1. Direct forward append (fast path)
        if currentNewText.hasPrefix(previousText) {
            let suffixIndex = currentNewText.index(currentNewText.startIndex, offsetBy: previousText.count)
            let delta = String(currentNewText[suffixIndex...])
            guard !delta.isEmpty else { return }
            typeUnicodeString(delta)
            previousText = currentNewText
            return
        }
        
        // 2. Find common prefix length
        let newChars = Array(currentNewText)
        let oldChars = Array(previousText)
        var commonPrefixCount = 0
        let minLen = min(newChars.count, oldChars.count)
        
        while commonPrefixCount < minLen && newChars[commonPrefixCount] == oldChars[commonPrefixCount] {
            commonPrefixCount += 1
        }
        
        let backspaceCount = oldChars.count - commonPrefixCount
        
        // 3. Strict Speech pause boundary detection:
        // When speech resumes after a pause, Apple ASR starts a new utterance.
        // If common prefix <= 1 and previous utterance had substantial characters (>= 4),
        // NEVER delete previous words! Smoothly bridge with punctuation and append the new utterance directly at the cursor.
        if commonPrefixCount <= 1 && oldChars.count >= 4 {
            let punctuationSet: Set<Character> = ["。", "，", "！", "？", "；", "…", ".", ",", "!", "?", ";", " "]
            if let lastChar = previousText.last, !punctuationSet.contains(lastChar) {
                let firstChar = currentNewText.first
                if firstChar == nil || !punctuationSet.contains(firstChar!) {
                    // Smart punctuation based on sentence ending
                    if previousText.hasSuffix("嗎") || previousText.hasSuffix("呢") || previousText.hasSuffix("吧") || previousText.hasSuffix("會不會") || previousText.hasSuffix("是不是") {
                        typeUnicodeString("？")
                    } else {
                        typeUnicodeString("，")
                    }
                }
            }
            typeUnicodeString(currentNewText)
            previousText = currentNewText
            return
        }
        
        // 4. Second-Pass Substantial Revision Protection:
        // If ASR makes a middle-sentence revision to text already typed on screen,
        // attempting to backspace > 4 characters in a live stream is unsafe (causes duplicate text in target apps).
        // Instead, check if newText is largely similar to previousText without new suffix:
        if backspaceCount > 4 {
            if newChars.count <= oldChars.count {
                // No new content at the tail; keep what's on screen and update tracking
                previousText = currentNewText
                return
            } else {
                // If there's new content at the tail, only type the extra new characters
                let extraCharsCount = newChars.count - oldChars.count
                let extraSuffix = String(newChars.suffix(extraCharsCount))
                typeUnicodeString(extraSuffix)
                previousText = currentNewText
                return
            }
        }
        
        // 5. Safe Local phonetic refinement within active utterance (small tail backspaces <= 4 chars)
        if backspaceCount > 0 {
            sendBackspaces(count: backspaceCount)
        }
        let deltaNew = String(newChars[commonPrefixCount...])
        if !deltaNew.isEmpty {
            typeUnicodeString(deltaNew)
        }
        previousText = currentNewText
    }
    
    /// Simulate Cmd + V keyboard shortcut
    public func simulatePasteCommand() {
        let vKeyCode: CGKeyCode = 9 // Virtual key code for 'v'
        
        // Command key down + V key down
        let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true)
        eventDown?.flags = .maskCommand
        eventDown?.post(tap: .cghidEventTap)
        
        // V key up
        let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false)
        eventUp?.flags = .maskCommand
        eventUp?.post(tap: .cghidEventTap)
    }
    
    /// Check if Accessibility Permissions are granted
    public static func checkAccessibilityPermission() -> Bool {
        let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options = [checkOptPrompt: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
#else
public final class InputInjector: @unchecked Sendable {
    public static let shared = InputInjector()
    public init() {}
    public func inject(text: String, restoreClipboard: Bool = true) async -> Bool {
        return true
    }
    public func typeUnicodeString(_ string: String) {}
    public func sendBackspaces(count: Int) {}
    public func injectStreamingDelta(newText: String, previousText: inout String) {
        previousText = newText
    }
}
#endif
