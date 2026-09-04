import Foundation

public enum ButterflyHotkeyIntent: Equatable, Sendable {
    case liveDictation
    case smartPolish
}

public enum GlobalHotkeyResolver {
    public static func resolve(
        keyCode: Int,
        optionPressed: Bool,
        shiftPressed: Bool,
        commandPressed: Bool,
        controlPressed: Bool
    ) -> ButterflyHotkeyIntent? {
        guard keyCode == 49,
              optionPressed,
              !commandPressed,
              !controlPressed else {
            return nil
        }
        return shiftPressed ? .smartPolish : .liveDictation
    }
}
