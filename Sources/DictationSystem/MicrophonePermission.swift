import AVFoundation

/// Coalesces startup and button requests. Granting access never starts a recorder.
@MainActor
public final class MicrophonePermission {
    private let status: @MainActor () -> AVAuthorizationStatus
    private let request: @MainActor () async -> Bool
    private var pending: Task<Bool, Never>?

    public init(
        status: @escaping @MainActor () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .audio) },
        request: @escaping @MainActor () async -> Bool = { await AVCaptureDevice.requestAccess(for: .audio) }
    ) {
        self.status = status
        self.request = request
    }

    public func requestIfNeeded() async -> Bool {
        if let pending { return await pending.value }
        switch status() {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            let request = request
            let task = Task { await request() }
            pending = task
            let granted = await task.value
            pending = nil
            return granted
        @unknown default: return false
        }
    }
}
