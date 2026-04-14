import Foundation

/// Owns at most one ``VaultDirectoryWatcher`` per vault path and fans out debounced events to subscribers.
@MainActor
final class VaultWatcherHub {
    static let shared = VaultWatcherHub()

    private struct Subscriber {
        var onSetupFailed: (@MainActor (Error) -> Void)?
        var onEvent: @MainActor () -> Void
    }

    private struct Entry {
        var watcher: VaultDirectoryWatcher?
        var subscribers: [UUID: Subscriber] = [:]
    }

    private var entries: [String: Entry] = [:]

    private init() {}

    /// Subscribes to filesystem events under `vaultURL`. Return value keeps the subscription alive.
    func subscribe(
        vaultURL: URL,
        onSetupFailed: (@MainActor (Error) -> Void)? = nil,
        onEvent: @escaping @MainActor () -> Void
    ) -> VaultWatcherSubscription {
        let key = vaultURL.standardizedFileURL.path
        let id = UUID()

        var entry = entries[key] ?? Entry()
        entry.subscribers[id] = Subscriber(onSetupFailed: onSetupFailed, onEvent: onEvent)
        entries[key] = entry

        ensureWatcherStarted(vaultURL: vaultURL, key: key)

        return VaultWatcherSubscription(hub: self, vaultKey: key, subscriberID: id)
    }

    private func ensureWatcherStarted(vaultURL: URL, key: String) {
        guard var entry = entries[key] else { return }
        if entry.watcher != nil { return }

        entry.watcher = VaultDirectoryWatcher(
            vaultURL: vaultURL,
            onSetupFailed: { [weak self] error in
                guard let self else { return }
                Task { @MainActor in
                    self.notifySetupFailed(vaultKey: key, error: error)
                }
            },
            onEvent: { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.dispatchEvent(vaultKey: key)
                }
            }
        )
        entries[key] = entry
    }

    private func notifySetupFailed(vaultKey: String, error: Error) {
        guard let entry = entries[vaultKey] else { return }
        for sub in entry.subscribers.values {
            sub.onSetupFailed?(error)
        }
    }

    fileprivate func removeSubscriber(vaultKey: String, id: UUID) {
        guard var entry = entries[vaultKey] else { return }
        entry.subscribers[id] = nil
        if entry.subscribers.isEmpty {
            entry.watcher?.cancel()
            entry.watcher = nil
            entries[vaultKey] = nil
        } else {
            entries[vaultKey] = entry
        }
    }

    private func dispatchEvent(vaultKey: String) {
        guard let entry = entries[vaultKey] else { return }
        for sub in entry.subscribers.values {
            sub.onEvent()
        }
    }

#if DEBUG
    /// Triggers the same fan-out as a debounced FSEvent (for tests).
    func simulateEvent(forVaultPath vaultPath: String) {
        dispatchEvent(vaultKey: vaultPath)
    }
#endif
}

/// Keeps the subscription registered until deallocated.
@MainActor
final class VaultWatcherSubscription {
    private let hub: VaultWatcherHub
    private let vaultKey: String
    private let subscriberID: UUID

    init(hub: VaultWatcherHub, vaultKey: String, subscriberID: UUID) {
        self.hub = hub
        self.vaultKey = vaultKey
        self.subscriberID = subscriberID
    }

    deinit {
        let hub = hub
        let vaultKey = vaultKey
        let subscriberID = subscriberID
        Task { @MainActor in
            hub.removeSubscriber(vaultKey: vaultKey, id: subscriberID)
        }
    }
}
