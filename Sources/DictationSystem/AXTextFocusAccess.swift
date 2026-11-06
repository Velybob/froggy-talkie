import AppKit
@preconcurrency import ApplicationServices

struct AXFocusElement: Equatable {
    let value: AXUIElement
    static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.value, rhs.value) }
}

@MainActor
struct AXTextFocusAccess: TextFocusAccess {
    var frontmostPID: Int32? { NSWorkspace.shared.frontmostApplication?.processIdentifier }

    func focusedCandidates(pid: Int32) -> [AXFocusElement] {
        let app = application(pid)
        let window = elementAttribute(app, kAXFocusedWindowAttribute)
        // The app, system-wide focus and focused window may expose different parts of a web editor.
        let roots = [elementAttribute(app, kAXFocusedUIElementAttribute),
                     elementAttribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute),
                     window.flatMap { elementAttribute($0, kAXFocusedUIElementAttribute) }].compactMap { $0 }
        var result: [AXFocusElement] = []
        for root in roots {
            var chain: [AXFocusElement] = []
            var next: AXUIElement? = root
            while let element = next, chain.count < 8 {
                let wrapped = AXFocusElement(value: element)
                var owner: pid_t = 0
                guard AXUIElementGetPid(element, &owner) == .success, owner == pid,
                      !chain.contains(wrapped) else { break }
                chain.append(wrapped)
                next = elementAttribute(element, kAXFocusedUIElementAttribute)
            }
            for element in chain.reversed() where !result.contains(element) { result.append(element) }
        }
        return result
    }

    func enableAccessibility(pid: Int32) {
        let app = application(pid)
        // Electron's documented assistive-technology API; unsupported apps simply reject it.
        // https://www.electronjs.org/docs/latest/tutorial/accessibility#macos
        _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        // Chromium can expose this on the app or its focused window. Do not toggle it off:
        // other assistive technology may also be using the tree.
        for element in [app, elementAttribute(app, kAXFocusedWindowAttribute)].compactMap({ $0 }) {
            var settable = DarwinBoolean(false)
            let name = "AXEnhancedUserInterface" as CFString
            if AXUIElementIsAttributeSettable(element, name, &settable) == .success, settable.boolValue {
                _ = AXUIElementSetAttributeValue(element, name, kCFBooleanTrue)
            }
        }
    }

    func kind(of element: AXFocusElement) -> TextFocusKind {
        if isSecure(element) { return .secure }
        return selectedRange(element) != nil || isEditableTextField(element) ? .editable : .other
    }

    func selectedRange(_ element: AXFocusElement) -> TextSelection? {
        guard let value = attribute(element.value, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return TextSelection(location: range.location, length: range.length)
    }

    func isSecure(_ element: AXFocusElement) -> Bool {
        var current: AXUIElement? = element.value
        var visited: [AXFocusElement] = []
        while let node = current, visited.count < 8 {
            let wrapped = AXFocusElement(value: node)
            guard !visited.contains(wrapped) else { break }
            visited.append(wrapped)
            if (attribute(node, kAXSubroleAttribute) as? String) == (kAXSecureTextFieldSubrole as String) { return true }
            current = elementAttribute(node, kAXParentAttribute)
        }
        return false
    }

    func isEditableTextField(_ element: AXFocusElement) -> Bool {
        guard let role = attribute(element.value, kAXRoleAttribute) as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else { return false }
        if let enabled = attribute(element.value, kAXEnabledAttribute) as? Bool, !enabled { return false }
        return true
    }

    private func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        return app
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let result = value as! AXUIElement
        AXUIElementSetMessagingTimeout(result, 0.25)
        return result
    }
}
