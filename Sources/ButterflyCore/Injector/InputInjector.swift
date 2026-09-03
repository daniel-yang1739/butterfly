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
    public func inject(text: String, restoreClipboard: Bool = false) async -> Bool {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return false }
        
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        
        // 1. Write clean text to pasteboard
        pasteboard.clearContents()
        pasteboard.setString(cleanText, forType: .string)
        
        // Short pause to ensure pasteboard server commits data before keystroke
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // 2. Simulate Cmd + V paste keystroke
        simulatePasteCommand()
        
        // 3. Optional clipboard restoration after a generous safety window (2s)
        if restoreClipboard, let original = previousString {
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                pasteboard.clearContents()
                pasteboard.setString(original, forType: .string)
            }
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
            usleep(1500) // 1.5ms delay to ensure event queues process each backspace
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
        
        // 3. Clean in-place refinement for active utterance
        if backspaceCount > 0 && backspaceCount <= 25 {
            sendBackspaces(count: backspaceCount)
            let deltaNew = String(newChars[commonPrefixCount...])
            if !deltaNew.isEmpty {
                typeUnicodeString(deltaNew)
            }
            previousText = currentNewText
            return
        } else if backspaceCount > 25 {
            // If the shift is larger than 25 chars, avoid destructive backspacing; only append trailing difference
            if newChars.count > oldChars.count {
                let extraCount = newChars.count - oldChars.count
                let extraSuffix = String(newChars.suffix(extraCount))
                typeUnicodeString(extraSuffix)
            }
            previousText = currentNewText
            return
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
        
        // Short pause between down and up
        usleep(20000) // 20ms
        
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
    public func inject(text: String, restoreClipboard: Bool = false) async -> Bool {
        return true
    }
    public func typeUnicodeString(_ string: String) {}
    public func sendBackspaces(count: Int) {}
    public func injectStreamingDelta(newText: String, previousText: inout String) {
        previousText = newText
    }
}
#endif
