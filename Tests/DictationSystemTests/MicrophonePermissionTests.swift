import AVFoundation
import Testing
@testable import DictationSystem

@Test @MainActor func existingMicrophoneDecisionsNeverPromptAgain() async {
    for status: AVAuthorizationStatus in [.authorized, .denied, .restricted] {
        var requests = 0
        let permission = MicrophonePermission(status: { status }, request: { requests += 1; return true })
        #expect(await permission.requestIfNeeded() == (status == .authorized))
        #expect(requests == 0)
    }
}

@Test @MainActor func firstMicrophoneDecisionIsReturnedWithoutRepeatingThePrompt() async {
    for granted in [true, false] {
        var status = AVAuthorizationStatus.notDetermined
        var requests = 0
        let permission = MicrophonePermission(status: { status }, request: {
            requests += 1
            status = granted ? .authorized : .denied
            return granted
        })
        #expect(await permission.requestIfNeeded() == granted)
        #expect(await permission.requestIfNeeded() == granted)
        #expect(requests == 1)
    }
}

@Test @MainActor func startupAndRecordButtonShareOnePendingMicrophonePrompt() async throws {
    var status = AVAuthorizationStatus.notDetermined
    var requests = 0
    var reply: CheckedContinuation<Bool, Never>?
    let permission = MicrophonePermission(status: { status }, request: {
        requests += 1
        return await withCheckedContinuation { reply = $0 }
    })
    let startup = Task { await permission.requestIfNeeded() }
    while reply == nil { await Task.yield() }
    let button = Task { await permission.requestIfNeeded() }
    await Task.yield()
    // Closing the startup window does not create a second permission request.
    startup.cancel()
    status = .authorized
    try #require(reply).resume(returning: true)
    #expect(await startup.value)
    #expect(await button.value)
    #expect(requests == 1)
}
