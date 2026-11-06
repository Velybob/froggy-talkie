import AppKit
@preconcurrency import ApplicationServices
import Carbon

public struct TextSelection: Equatable, Sendable {
    public let location: Int
    public let length: Int
    public init(location: Int, length: Int) { self.location = location; self.length = length }
}

public enum InsertionGuard {
    public static func permits(originalPID: Int32, currentPID: Int32, sameElement: Bool,
        originalSelection: TextSelection?, currentSelection: TextSelection?, secure: Bool,
        editableTextField: Bool = false) -> Bool {
        guard originalPID == currentPID, sameElement, !secure else { return false }
        if let originalSelection { return originalSelection == currentSelection }
        // Some text editors expose a focused text field but no selection range.
        // In this mode we can verify the field, but cannot detect caret moves inside it.
        return editableTextField
    }
}

@MainActor
public final class TextInsertion {
    public struct Target {
        fileprivate let pid: pid_t
        fileprivate let element: AXUIElement
        fileprivate let selection: TextSelection?
        public let applicationName: String
    }
    public enum Result { case sent(String), retained(String) }
    private var restoreTask: Task<Void, Never>?
    private var pendingRestore: (PasteboardSnapshot, Int)?

    public init() {}
    public var isTrusted: Bool { AXIsProcessTrusted() }

    public func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public func captureTarget() throws -> Target {
        guard isTrusted else { throw Failure("Для вставки разреши «Универсальный доступ» в окне диктовки.") }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw Failure("Перейди в редактор и поставь курсор в текстовое поле.")
        }
        guard let element = focusedElement(pid: app.processIdentifier) else {
            throw Failure("Редактор не сообщает активное поле. Текст останется в окне диктовки.")
        }
        guard !isSecure(element) else { throw Failure("Вставка в поле пароля отключена. Текст останется в окне диктовки.") }
        let selection = selectedRange(element)
        guard selection != nil || isEditableTextField(element) else {
            throw Failure("Не удалось подтвердить текстовое поле. Текст останется в окне диктовки.")
        }
        return Target(pid: app.processIdentifier, element: element, selection: selection,
            applicationName: app.localizedName ?? "редактор")
    }

    public func insert(_ text: String, into target: Target) async -> Result {
        guard !text.isEmpty else { return .retained("Речь не распознана.") }
        // Carbon may deliver key-up while Control/Option are still physically held.
        let modifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
        for _ in 0..<100 {
            if Task.isCancelled { return .retained("Вставка отменена; текст сохранён в окне.") }
            if CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty else {
            return .retained("Клавиши всё ещё удерживаются; текст сохранён в окне.")
        }
        guard !Task.isCancelled, isTrusted, targetIsUnchanged(target) else {
            return .retained("Фокус или курсор изменился; текст сохранён в окне диктовки.")
        }
        restorePendingClipboard()
        let board = NSPasteboard.general
        guard let snapshot = PasteboardSnapshot.capture(from: board) else {
            return .retained("Не удалось сохранить буфер обмена; текст доступен в окне диктовки.")
        }
        guard targetIsUnchanged(target), board.changeCount == snapshot.originalChangeCount,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            return .retained("Вставка недоступна; текст сохранён в окне диктовки.")
        }
        board.clearContents()
        guard board.setString(text, forType: .string) else {
            snapshot.restore(to: board, ifUnchangedSince: board.changeCount)
            return .retained("Не удалось подготовить вставку; текст сохранён в окне.")
        }
        let ownedCount = board.changeCount
        down.flags = .maskCommand
        up.flags = .maskCommand
        // Route to the captured process. Never synthesize Return or submit a form.
        down.postToPid(target.pid)
        up.postToPid(target.pid)
        pendingRestore = (snapshot, ownedCount)
        restoreTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.restorePendingClipboard()
        }
        // Posting an event is not a universal acknowledgement from a third-party editor.
        return .sent(target.applicationName)
    }

    public func restorePendingClipboard() {
        restoreTask?.cancel()
        restoreTask = nil
        if let (snapshot, count) = pendingRestore {
            snapshot.restore(to: .general, ifUnchangedSince: count)
        }
        pendingRestore = nil
    }

    private func targetIsUnchanged(_ target: Target) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let current = focusedElement(pid: app.processIdentifier) else { return false }
        return InsertionGuard.permits(originalPID: target.pid, currentPID: app.processIdentifier,
            sameElement: CFEqual(target.element, current), originalSelection: target.selection,
            currentSelection: selectedRange(current), secure: isSecure(current),
            editableTextField: isEditableTextField(current))
    }

    private func focusedElement(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)
        return element
    }

    private func selectedRange(_ element: AXUIElement) -> TextSelection? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return TextSelection(location: range.location, length: range.length)
    }

    private func isSecure(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value) == .success else { return false }
        return (value as? String) == (kAXSecureTextFieldSubrole as String)
    }

    private func isEditableTextField(_ element: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else { return false }
        var enabledValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledValue) == .success,
           let enabled = enabledValue as? Bool, !enabled { return false }
        return true
    }

    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
