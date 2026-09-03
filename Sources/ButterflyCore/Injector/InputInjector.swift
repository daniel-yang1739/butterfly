import Foundation
#if os(macOS)
import AppKit
import ApplicationServices

/// Action to apply to the focused OS cursor to synchronize with streaming text
public enum SlidingDeltaAction: Equatable, Sendable {
    /// Pure forward character append (0 backspaces)
    case append(text: String)
    /// In-place suffix replacement with minimal backspaces
    case replaceTail(backspaces: Int, replacement: String)
    /// No keystroke action needed
    case noChange
}

/// Active window text injector and clipboard protection proxy
public final class InputInjector: @unchecked Sendable {
    public static let shared = InputInjector()
    private let injectionQueue = DispatchQueue(label: "com.butterfly.input-injector", qos: .userInteractive)
    
    public init() {}
    
    /// Inject a block of text into the active focused input using direct Unicode typing and pasteboard sync
    @discardableResult
    public func inject(text: String, restoreClipboard: Bool = false) async -> Bool {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return false }
        
        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)
        
        // 1. Write clean text to pasteboard as backup
        pasteboard.clearContents()
        pasteboard.setString(cleanText, forType: .string)
        
        // Short pause to ensure focus stability
        try? await Task.sleep(nanoseconds: 30_000_000) // 30ms
        
        // 2. Direct Unicode Typing directly into the active cursor (100% reliable)
        typeUnicodeString(cleanText)
        
        // 3. Optional clipboard restoration after a generous safety window (3s)
        if restoreClipboard, let original = previousString {
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                pasteboard.clearContents()
                pasteboard.setString(original, forType: .string)
            }
        }
        
        return true
    }

    /// Live incremental Unicode typing directly into cursor via CGEvent (chunked safely to respect macOS 20-char limit)
    public func typeUnicodeString(_ string: String) {
        let utf16Chars = Array(string.utf16)
        guard !utf16Chars.isEmpty else { return }
        
        let chunkSize = 10
        var index = 0
        while index < utf16Chars.count {
            let end = min(index + chunkSize, utf16Chars.count)
            let chunk = Array(utf16Chars[index..<end])
            
            if let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
               let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                eventDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                eventDown.post(tap: .cghidEventTap)
                
                eventUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                eventUp.post(tap: .cghidEventTap)
            }
            index = end
            if index < utf16Chars.count {
                usleep(3000) // 3ms pause between chunks to let target app text engine process
            }
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
            usleep(3000) // 3ms delay to ensure OS text field event queues process each backspace
        }
    }
    
    /// Apply SlidingDeltaAction directly to the active cursor
    public func applySlidingDelta(_ action: SlidingDeltaAction) {
        switch action {
        case .append(let text):
            guard !text.isEmpty else { return }
            typeUnicodeString(text)
        case .replaceTail(let backspaces, let replacement):
            if backspaces > 0 {
                sendBackspaces(count: backspaces)
                usleep(5000) // 5ms settlement delay to guarantee clean cursor state before typing replacement
            }
            if !replacement.isEmpty {
                typeUnicodeString(replacement)
            }
        case .noChange:
            break
        }
    }

    /// Queue cursor events away from the main thread while preserving transcript order.
    public func enqueueSlidingDelta(_ action: SlidingDeltaAction) {
        guard action != .noChange else { return }
        injectionQueue.async { [self] in
            applySlidingDelta(action)
        }
    }

    /// Calculate and record the next cursor change without posting keyboard events.
    public func prepareStreamingDelta(newText: String, previousText: inout String) -> SlidingDeltaAction {
        var currentNewText = newText
        if previousText.isEmpty {
            currentNewText = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard currentNewText != previousText else { return .noChange }

        if currentNewText.hasPrefix(previousText) {
            let suffixIndex = currentNewText.index(currentNewText.startIndex, offsetBy: previousText.count)
            let delta = String(currentNewText[suffixIndex...])
            previousText = currentNewText
            return delta.isEmpty ? .noChange : .append(text: delta)
        }

        let newCharacters = Array(currentNewText)
        let oldCharacters = Array(previousText)
        var commonPrefixCount = 0
        let sharedLength = min(newCharacters.count, oldCharacters.count)
        while commonPrefixCount < sharedLength,
              newCharacters[commonPrefixCount] == oldCharacters[commonPrefixCount] {
            commonPrefixCount += 1
        }

        let backspaceCount = oldCharacters.count - commonPrefixCount
        previousText = currentNewText

        if backspaceCount > 0 && backspaceCount <= 25 {
            return .replaceTail(
                backspaces: backspaceCount,
                replacement: String(newCharacters[commonPrefixCount...])
            )
        }
        if backspaceCount > 25 {
            guard newCharacters.count > oldCharacters.count else { return .noChange }
            return .append(text: String(newCharacters.suffix(newCharacters.count - oldCharacters.count)))
        }

        let delta = String(newCharacters[commonPrefixCount...])
        return delta.isEmpty ? .noChange : .append(text: delta)
    }

    /// Utterance-Aware Real-time Live Stream Typing
    public func injectStreamingDelta(newText: String, previousText: inout String) {
        applySlidingDelta(prepareStreamingDelta(newText: newText, previousText: &previousText))
    }
    
    /// Simulate Cmd + V keyboard shortcut
    public func simulatePasteCommand() {
        let vKeyCode: CGKeyCode = 9 // Virtual key code for 'v'
        
        // Command key down + V key down
        let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true)
        eventDown?.flags = .maskCommand
        eventDown?.post(tap: .cghidEventTap)
        
        // Short pause between down and up
        usleep(25000) // 25ms
        
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
