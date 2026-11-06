import Foundation

/// A release may arrive before asynchronous recorder preparation completes.
public struct HoldToTalkGate: Sendable {
    public enum Release: Equatable, Sendable { case none, cancelPending(UUID), finish(UUID) }
    private enum Phase: Sendable { case idle, arming(UUID), recording(UUID) }
    private var phase: Phase = .idle
    public private(set) var isHeld = false

    public init() {}

    public mutating func press(canStart: Bool, session: UUID) -> Bool {
        guard !isHeld else { return false }
        isHeld = true
        guard canStart else { return false }
        phase = .arming(session)
        return true
    }

    public mutating func recorderReady(session: UUID) -> Bool {
        guard isHeld, case .arming(let current) = phase, current == session else { return false }
        phase = .recording(session)
        return true
    }

    public mutating func release() -> Release {
        isHeld = false
        defer { phase = .idle }
        switch phase {
        case .idle: return .none
        case .arming(let session): return .cancelPending(session)
        case .recording(let session): return .finish(session)
        }
    }

    /// Keep the held latch until key-up, so autorepeat cannot restart a cancelled recording.
    public mutating func cancelSession() { phase = .idle }
}
