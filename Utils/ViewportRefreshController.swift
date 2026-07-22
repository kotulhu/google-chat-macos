import Foundation

@MainActor
final class ViewportRefreshController {
    private var visibleIds = Set<String>()
    private var debounceTasks = [String: Task<Void, Never>]()
    private var forceRefreshTimer: Timer?

    private let debounceInterval: TimeInterval
    private let forceRefreshInterval: TimeInterval
    private let onRefresh: (String) async -> Void

    init(
        debounceInterval: TimeInterval = 0.4,
        forceRefreshInterval: TimeInterval = 30.0,
        onRefresh: @escaping (String) async -> Void
    ) {
        self.debounceInterval = debounceInterval
        self.forceRefreshInterval = forceRefreshInterval
        self.onRefresh = onRefresh
    }

    func markVisible(id: String) {
        visibleIds.insert(id)
        debounceTasks[id]?.cancel()
        debounceTasks[id] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.debounceInterval))
            guard !Task.isCancelled, self.visibleIds.contains(id) else { return }
            await self.onRefresh(id)
        }
    }

    func markHidden(id: String) {
        visibleIds.remove(id)
        debounceTasks[id]?.cancel()
        debounceTasks.removeValue(forKey: id)
    }

    func start() {
        stop()
        forceRefreshTimer = Timer.scheduledTimer(withTimeInterval: forceRefreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.forceRefreshVisible() }
        }
    }

    func stop() {
        forceRefreshTimer?.invalidate()
        forceRefreshTimer = nil
        for task in debounceTasks.values { task.cancel() }
        debounceTasks.removeAll()
        visibleIds.removeAll()
    }

    private func forceRefreshVisible() async {
        let ids = Array(visibleIds)
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { [weak self] in
                    await self?.onRefresh(id)
                }
            }
        }
    }
}
