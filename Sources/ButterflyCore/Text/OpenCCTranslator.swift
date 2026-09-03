import Foundation
import OpenCC

/// Official OpenCC Traditional Chinese (Taiwan Standard / s2twp) translator
public final class OpenCCTranslator: @unchecked Sendable {
    public static let shared = OpenCCTranslator()
    
    private let converter: ChineseConverter?
    
    public init() {
        // Initialize official OpenCC converter with Taiwan standard & idiom phrasing (s2twp)
        self.converter = try? ChineseConverter(option: [.traditionalize, .TWStandard, .TWIdiom])
    }
    
    /// Convert text to Taiwan Traditional Chinese (s2twp standard) using official OpenCC package
    public func convert(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        
        // 1. Official OpenCC s2twp Conversion
        if let converter = self.converter {
            return converter.convert(text)
        }
        
        // 2. Fallback to macOS Native ICU Transliteration
        if let transformed = text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) {
            return transformed
        }
        
        return text
    }
    
    /// Check if text contains any remaining Simplified Chinese characters
    public func containsSimplified(_ text: String) -> Bool {
        let converted = convert(text)
        return converted != text
    }
}
