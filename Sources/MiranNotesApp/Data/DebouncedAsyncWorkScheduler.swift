import Foundation

/// Single-slot debounced async work on the main actor (cancels prior scheduled work when rescheduled).
@MainActor
final class DebouncedAsyncWorkScheduler {
    private var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        task = nil
    }

    func schedule(delay: Duration, _ work: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await work()
        }
    }
}
