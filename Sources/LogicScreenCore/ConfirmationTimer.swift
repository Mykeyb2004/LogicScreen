import Foundation

/// The expiry callback runs after the timer releases its task, so recovery can cancel
/// the timer without cancelling its own asynchronous display restoration.
@MainActor
public final class ConfirmationTimer {
    private var task: Task<Void, Never>?

    public init() {}

    public func start(duration: TimeInterval, tick: @escaping (Int) -> Void,
                      expired: @escaping () async -> Void) {
        cancel()
        let deadline = Date().addingTimeInterval(duration)
        tick(max(0, Int(ceil(duration))))
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self else { return }
                let remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
                tick(remaining)
                if remaining == 0 {
                    self.task = nil
                    await expired()
                    return
                }
            }
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }
}
