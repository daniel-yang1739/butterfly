import Foundation

/// Apple Native Traditional Chinese (Taiwan Standard) translator using macOS Foundation ICU Transliteration
public final class OpenCCTranslator {
    public static let shared = OpenCCTranslator()
    
    public init() {}
    
    /// Convert text to Traditional Chinese natively using macOS Foundation ICU engine
    public func convert(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        
        // 1. macOS Native ICU Hans-to-Hant Transliteration (Apple System Level)
        if let transformed = text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) {
            return transformed
        }
        
        return text
    }
    
    /// Check if text contains any remaining Simplified Chinese characters using Apple Native Transform
    public func containsSimplified(_ text: String) -> Bool {
        let converted = convert(text)
        return converted != text
    }
}
