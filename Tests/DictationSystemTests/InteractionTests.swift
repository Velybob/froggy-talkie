import AppKit
import Foundation
import Testing
@testable import DictationSystem

@Test func releaseBeforeRecorderIsReadyCannotStartRecording() {
    var gate = HoldToTalkGate()
    let id = UUID()
    #expect(gate.press(canStart: true, session: id) == true)
    #expect(gate.release() == .cancelPending(id))
    #expect(gate.recorderReady(session: id) == false)
}

@Test func holdFinishesExactlyOnceAndIgnoresAutorepeat() {
    var gate = HoldToTalkGate()
    let id = UUID()
    #expect(gate.press(canStart: true, session: id) == true)
    #expect(gate.press(canStart: true, session: UUID()) == false)
    #expect(gate.recorderReady(session: id) == true)
    #expect(gate.release() == .finish(id))
    #expect(gate.release() == .none)
}

@Test func cancellationAndBusyPressRequireAReleaseBeforeRestart() {
    var gate = HoldToTalkGate()
    #expect(gate.press(canStart: true, session: UUID()) == true)
    gate.cancelSession()
    #expect(gate.press(canStart: true, session: UUID()) == false)
    #expect(gate.release() == .none)
    #expect(gate.press(canStart: false, session: UUID()) == false)
    #expect(gate.press(canStart: true, session: UUID()) == false)
    #expect(gate.release() == .none)
    #expect(gate.press(canStart: true, session: UUID()) == true)
}

@Test func insertionRejectsOtherAppFieldCaretAndSecureInput() {
    let selection = TextSelection(location: 8, length: 0)
    #expect(InsertionGuard.permits(originalPID: 1, currentPID: 1, sameElement: true,
        originalSelection: selection, currentSelection: selection, secure: false))
    #expect(!InsertionGuard.permits(originalPID: 1, currentPID: 2, sameElement: true,
        originalSelection: selection, currentSelection: selection, secure: false))
    #expect(!InsertionGuard.permits(originalPID: 1, currentPID: 1, sameElement: false,
        originalSelection: selection, currentSelection: selection, secure: false))
    #expect(!InsertionGuard.permits(originalPID: 1, currentPID: 1, sameElement: true,
        originalSelection: selection, currentSelection: TextSelection(location: 3, length: 0), secure: false))
    #expect(!InsertionGuard.permits(originalPID: 1, currentPID: 1, sameElement: true,
        originalSelection: selection, currentSelection: nil, secure: false))
    #expect(!InsertionGuard.permits(originalPID: 1, currentPID: 1, sameElement: true,
        originalSelection: selection, currentSelection: selection, secure: true))
}

@Test @MainActor func clipboardRestoresAllRepresentationsButPreservesNewUserCopy() throws {
    let board = NSPasteboard(name: .init("LocalDictationTests-\(UUID())"))
    defer { board.releaseGlobally() }
    let original = NSPasteboardItem()
    original.setString("original", forType: .string)
    original.setData(Data([0, 1, 2, 3]), forType: .png)
    board.clearContents()
    #expect(board.writeObjects([original]))
    let snapshot = try #require(PasteboardSnapshot.capture(from: board))
    board.clearContents()
    board.setString("dictation", forType: .string)
    #expect(snapshot.restore(to: board, ifUnchangedSince: board.changeCount))
    #expect(board.string(forType: .string) == "original")
    #expect(board.data(forType: .png) == Data([0, 1, 2, 3]))
    board.clearContents()
    board.setString("dictation again", forType: .string)
    let owned = board.changeCount
    board.clearContents()
    board.setString("new user copy", forType: .string)
    #expect(!snapshot.restore(to: board, ifUnchangedSince: owned))
    #expect(board.string(forType: .string) == "new user copy")
    #expect(PasteboardSnapshot.capture(from: board, maxBytes: 1) == nil)
}

@Test func staleRecorderPreparationCannotEnterANewSession() {
    var gate = HoldToTalkGate()
    let old = UUID()
    let current = UUID()
    #expect(gate.press(canStart: true, session: old) == true)
    #expect(gate.release() == .cancelPending(old))
    #expect(gate.press(canStart: true, session: current) == true)
    #expect(gate.recorderReady(session: old) == false)
    #expect(gate.recorderReady(session: current) == true)
    #expect(gate.release() == .finish(current))
}
