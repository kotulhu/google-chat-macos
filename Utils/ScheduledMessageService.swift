import Foundation

/// Periodically fires scheduled messages whose send-time has arrived, reusing
/// the existing send path through an injected closure. Modeled after
/// `ViewportRefreshController`: an isolated `@MainActor` controller owned by
/// `ChatViewModel` with explicit `start()`/`stop()` lifecycle. The queue itself
/// lives in `ScheduledMessageStore` — this type only watches it and fires.
@MainActor
final class ScheduledMessageService {
    private let store: ScheduledMessageStore
    private let onFire: (ScheduledMessage) async -> Bool
    private var timer: Timer?

    init(store: ScheduledMessageStore, onFire: @escaping (ScheduledMessage) async -> Bool) {
        self.store = store
        self.onFire = onFire
    }

    func start() {
        stop()
        // Check once immediately (covers entries scheduled a few seconds out),
        // then sweep every 5 seconds while the app is open.
        Task { await checkDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.checkDue() }
        }
        print("⏰ ScheduledMessageService started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Sends every pending message whose time has arrived. Successful sends are
    /// removed from the queue; failures stay pending so the next tick retries.
    func checkDue() async {
        let now = Date()
        let due = store.entries.values
            .filter { $0.status == .pending && $0.scheduledAt <= now }
        for message in due {
            let sent = await onFire(message)
            if sent {
                store.remove(spaceId: message.spaceId)
            }
        }
    }
}