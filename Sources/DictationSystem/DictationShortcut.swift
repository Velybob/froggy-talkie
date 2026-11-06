import Carbon
import Foundation

/// Carbon key codes identify physical keys, so switching RU/EN does not change the shortcut.
public struct DictationShortcut: Codable, Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let `default` = Self(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))
    public static let allowedModifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)
    public var isValid: Bool {
        Self.labels[keyCode] != nil && modifiers & ~Self.allowedModifiers == 0
            && modifiers & UInt32(controlKey | optionKey | cmdKey) != 0
    }
    public var keyLabel: String { Self.labels[keyCode] ?? "?" }
    public var modifierSymbols: [String] {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .compactMap { modifiers & UInt32($0.0) != 0 ? $0.1 : nil }
    }
    public var display: String { modifierSymbols.joined() + keyLabel }
    public var accessibilityLabel: String {
        let names = [(controlKey, "Control"), (optionKey, "Option"), (shiftKey, "Shift"), (cmdKey, "Command")]
            .compactMap { modifiers & UInt32($0.0) != 0 ? $0.1 : nil }
        return (names + [keyLabel]).joined(separator: ", ")
    }

    // Standard physical key labels are stable across layouts and stored preferences.
    private static let labels: [UInt32: String] = [
        0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V", 11:"B",
        12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 18:"1", 19:"2", 20:"3", 21:"4",
        22:"6", 23:"5", 24:"=", 25:"9", 26:"7", 27:"−", 28:"8", 29:"0", 30:"]", 31:"O",
        32:"U", 33:"[", 34:"I", 35:"P", 36:"↩", 37:"L", 38:"J", 39:"’", 40:"K", 41:";",
        42:"\\", 43:",", 44:"/", 45:"N", 46:"M", 47:".", 48:"⇥", 49:"Пробел", 50:"`",
        51:"⌫", 53:"Esc", 65:"Num .", 67:"Num *", 69:"Num +", 71:"Clear", 75:"Num /",
        76:"Num ↩", 78:"Num −", 81:"Num =", 82:"Num 0", 83:"Num 1", 84:"Num 2",
        85:"Num 3", 86:"Num 4", 87:"Num 5", 88:"Num 6", 89:"Num 7", 91:"Num 8", 92:"Num 9",
        64:"F17", 79:"F18", 80:"F19", 90:"F20", 96:"F5", 97:"F6", 98:"F7", 99:"F3",
        100:"F8", 101:"F9", 103:"F11", 105:"F13", 106:"F16", 107:"F14", 109:"F10",
        111:"F12", 113:"F15", 114:"Help", 115:"Home", 116:"Page Up", 117:"⌦", 118:"F4",
        119:"End", 120:"F2", 121:"Page Down", 122:"F1", 123:"←", 124:"→", 125:"↓", 126:"↑",
    ]
}
