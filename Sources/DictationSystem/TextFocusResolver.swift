import Foundation

enum TextFocusKind { case editable, secure, other }

@MainActor
protocol TextFocusAccess {
    associatedtype Element: Equatable
    var frontmostPID: Int32? { get }
    func focusedCandidates(pid: Int32) -> [Element]
    func kind(of element: Element) -> TextFocusKind
    func enableAccessibility(pid: Int32)
}

enum TextFocusFailure: Error { case changedApplication, secure, unavailable }

/// Retries only the original foreground application, never searches arbitrary text fields.
@MainActor
struct TextFocusResolver<Access: TextFocusAccess> {
    let access: Access

    func current(pid: Int32) throws -> Access.Element? {
        guard access.frontmostPID == pid else { throw TextFocusFailure.changedApplication }
        let candidates = access.focusedCandidates(pid: pid).map { ($0, access.kind(of: $0)) }
        // Conflicting sources must not let an editable ancestor hide a secure focused child.
        guard !candidates.contains(where: { $0.1 == .secure }) else { throw TextFocusFailure.secure }
        guard access.frontmostPID == pid else { throw TextFocusFailure.changedApplication }
        return candidates.first(where: { $0.1 == .editable })?.0
    }

    func resolve(pid: Int32,
                 wait: @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async throws -> Access.Element {
        try Task.checkCancellation()
        if let element = try current(pid: pid) { return element }
        // Electron/Chromium can expose an empty tree until assistive technology enables it.
        access.enableAccessibility(pid: pid)
        for delay in [Duration.zero, .milliseconds(50), .milliseconds(100), .milliseconds(200)] {
            if delay != .zero { try await wait(delay) }
            try Task.checkCancellation()
            if let element = try current(pid: pid) { return element }
        }
        throw TextFocusFailure.unavailable
    }
}
