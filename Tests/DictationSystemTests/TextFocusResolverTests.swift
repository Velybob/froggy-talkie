import Foundation
import Testing
@testable import DictationSystem

@MainActor
private final class FocusFixture: TextFocusAccess {
    var frontmostPID: Int32? = 42
    var candidates: [Int] = []
    var kinds: [Int: TextFocusKind] = [1: .editable, 2: .secure, 3: .other]
    var enabled = 0
    var reads = 0
    func focusedCandidates(pid: Int32) -> [Int] { reads += 1; return candidates }
    func kind(of element: Int) -> TextFocusKind { kinds[element] ?? .other }
    func enableAccessibility(pid: Int32) { enabled += 1 }
}

@Test @MainActor func nativeTextFieldDoesNotNeedAccessibilityActivationOrDelay() async throws {
    let access = FocusFixture()
    access.candidates = [1]
    let element = try await TextFocusResolver(access: access).resolve(pid: 42, wait: { _ in
        Issue.record("Native focus should resolve immediately")
    })
    #expect(element == 1)
    #expect(access.enabled == 0)
}

@Test @MainActor func lazyWebAccessibilityTreeBecomesAvailableAfterActivation() async throws {
    let access = FocusFixture()
    access.candidates = [3] // A web container, not an editable field.
    var waits = 0
    let element = try await TextFocusResolver(access: access).resolve(pid: 42, wait: { _ in
        waits += 1
        if waits == 2 { access.candidates = [3, 1] }
    })
    #expect(element == 1)
    #expect(access.enabled == 1)
    #expect(waits == 2)
}

@Test @MainActor func unsupportedEditorDoesNotFallBackToBlindPaste() async {
    let access = FocusFixture()
    access.candidates = [3]
    var waits = 0
    do {
        _ = try await TextFocusResolver(access: access).resolve(pid: 42, wait: { _ in waits += 1 })
        Issue.record("An unverified field must not be accepted")
    } catch TextFocusFailure.unavailable { }
    catch { Issue.record("Unexpected error: \(error)") }
    #expect(waits == 3)
    #expect(access.reads == 5)
    #expect(access.enabled == 1)
}

@Test @MainActor func focusResolutionDoesNotFollowTheUserIntoAnotherApplication() async {
    let access = FocusFixture()
    do {
        _ = try await TextFocusResolver(access: access).resolve(pid: 42, wait: { _ in
            access.frontmostPID = 99
            access.candidates = [1]
        })
        Issue.record("Must reject an application switch during preparation")
    } catch TextFocusFailure.changedApplication { }
    catch { Issue.record("Unexpected error: \(error)") }
}

@Test @MainActor func secureFocusIsRejectedEvenIfAnotherSourceReportsEditableText() async {
    let access = FocusFixture()
    for candidates in [[2, 1], [1, 2]] {
        access.candidates = candidates
        do {
            _ = try await TextFocusResolver(access: access).resolve(pid: 42)
            Issue.record("Must reject secure focus regardless of source order")
        } catch TextFocusFailure.secure { }
        catch { Issue.record("Unexpected error: \(error)") }
    }
    #expect(access.enabled == 0)
}

@Test @MainActor func releasingHotKeyWhileTreeLoadsCancelsFocusPreparation() async throws {
    let access = FocusFixture()
    var enteredWait = false
    let pending = Task {
        try await TextFocusResolver(access: access).resolve(pid: 42, wait: { _ in
            enteredWait = true
            try await Task.sleep(for: .seconds(10))
        })
    }
    while !enteredWait { await Task.yield() }
    pending.cancel()
    do {
        _ = try await pending.value
        Issue.record("Cancelled preparation must not return a field")
    } catch is CancellationError { }
    #expect(access.reads == 2)
}

@Test @MainActor func initialApplicationMismatchDoesNotEnableAccessibility() async {
    let access = FocusFixture()
    access.frontmostPID = 99
    do {
        _ = try await TextFocusResolver(access: access).resolve(pid: 42)
        Issue.record("Must keep the application captured at hotkey down")
    } catch TextFocusFailure.changedApplication { }
    catch { Issue.record("Unexpected error: \(error)") }
    #expect(access.enabled == 0)
    #expect(access.reads == 0)
}

@Test func editorWithoutSelectionStillRequiresSameVerifiedField() {
    #expect(InsertionGuard.permits(originalPID: 42, currentPID: 42, sameElement: true,
        originalSelection: nil, currentSelection: nil, secure: false, editableTextField: true))
    #expect(!InsertionGuard.permits(originalPID: 42, currentPID: 42, sameElement: false,
        originalSelection: nil, currentSelection: nil, secure: false, editableTextField: true))
    #expect(!InsertionGuard.permits(originalPID: 42, currentPID: 42, sameElement: true,
        originalSelection: nil, currentSelection: nil, secure: false, editableTextField: false))
}
