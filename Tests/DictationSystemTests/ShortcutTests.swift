import Carbon
import Foundation
import Testing
@testable import DictationSystem

@Test func shortcutRejectsBareKeysModifierKeysAndCorruptPreferences() throws {
    #expect(!DictationShortcut(keyCode: 0, modifiers: 0).isValid)
    #expect(!DictationShortcut(keyCode: 0, modifiers: UInt32(shiftKey)).isValid)
    #expect(!DictationShortcut(keyCode: 56, modifiers: UInt32(controlKey)).isValid)
    #expect(!DictationShortcut(keyCode: 999, modifiers: UInt32(controlKey)).isValid)
    #expect(!DictationShortcut(keyCode: 49, modifiers: UInt32(controlKey) | (1 << 31)).isValid)
    let decoded = try JSONDecoder().decode(DictationShortcut.self,
        from: Data(#"{"keyCode":999,"modifiers":4096}"#.utf8))
    #expect(!decoded.isValid)
}

@Test func shortcutRoundTripKeepsPhysicalKeyAndReadableModifiers() throws {
    let shortcut = DictationShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | shiftKey))
    #expect(shortcut.isValid)
    #expect(shortcut.display == "⌃⇧Пробел")
    #expect(shortcut.accessibilityLabel == "Control, Shift, Пробел")
    #expect(try JSONDecoder().decode(DictationShortcut.self, from: JSONEncoder().encode(shortcut)) == shortcut)
    #expect(DictationShortcut.default.display == "⌃⌥Пробел")
}

@Suite(.serialized) @MainActor
struct HotKeyRegistrationTests {
    // Temporarily register uncommon four-modifier function keys. Never send key
    // events, start a recording, or modify system shortcut preferences.
    @Test func failedReplacementKeepsThePreviousRegistrationAndReleaseFreesIt() throws {
        let modifiers = DictationShortcut.allowedModifiers
        let original = DictationShortcut(keyCode: UInt32(kVK_F19), modifiers: modifiers)
        let occupied = DictationShortcut(keyCode: UInt32(kVK_F18), modifiers: modifiers)
        let owner = GlobalHotKey(pressed: {}, released: {})
        let blocker = GlobalHotKey(pressed: {}, released: {})
        let probe = GlobalHotKey(pressed: {}, released: {})
        defer { owner.unregister(); blocker.unregister(); probe.unregister() }
        try owner.register(shortcut: original)
        try blocker.register(shortcut: occupied)
        #expect(throws: (any Error).self) { try owner.register(shortcut: occupied) }
        #expect(throws: (any Error).self) { try probe.register(shortcut: original) }
        try owner.register(shortcut: original) // Reusing our own registration is harmless.
        owner.unregister()
        try probe.register(shortcut: original)
        blocker.unregister()
        try probe.register(shortcut: occupied) // Successful replacement releases the old key.
        try owner.register(shortcut: original)
    }
}
