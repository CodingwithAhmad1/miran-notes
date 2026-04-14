import CoreServices
import Dispatch
import Foundation

/// Recursive vault watching using the File System Events API (subtree changes under `vaultURL`).
/// Debounces bursts before invoking `onEvent` on the main actor.
final class VaultDirectoryWatcher {
    private var stream: FSEventStreamRef? = nil
    private let debounceNanoseconds: UInt64
    private var debounceTask: Task<Void, Never>?
    private let onEvent: @MainActor () -> Void

    /// Debounce-only watcher for tests (no FSEvent stream).
    internal init(
        debounceMillisecondsForTests debounceMilliseconds: UInt64,
        onEvent: @escaping @MainActor () -> Void
    ) {
        self.debounceNanoseconds = debounceMilliseconds * 1_000_000
        self.onEvent = onEvent
        self.stream = nil
    }

    init(
        vaultURL: URL,
        debounceMilliseconds: UInt64 = 150,
        onSetupFailed: (@MainActor (Error) -> Void)? = nil,
        onEvent: @escaping @MainActor () -> Void
    ) {
        self.debounceNanoseconds = debounceMilliseconds * 1_000_000
        self.onEvent = onEvent
        self.stream = nil

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let paths = [vaultURL.path] as [String] as CFArray
        let sinceWhen = FSEventStreamEventId(UInt64(kFSEventStreamEventIdSinceNow))
        let latency: CFTimeInterval = 0.05
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)

        guard
            let streamRef = FSEventStreamCreate(
                kCFAllocatorDefault,
                VaultDirectoryWatcher.fsCallback,
                &context,
                paths,
                sinceWhen,
                latency,
                flags
            )
        else {
            let error = NSError(
                domain: "VaultDirectoryWatcher",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "FSEventStreamCreate returned nil"]
            )
            if let onSetupFailed {
                Task { @MainActor in
                    onSetupFailed(error)
                }
            }
            return
        }

        FSEventStreamSetDispatchQueue(streamRef, DispatchQueue.main)
        if !FSEventStreamStart(streamRef) {
            FSEventStreamInvalidate(streamRef)
            let error = NSError(
                domain: "VaultDirectoryWatcher",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "FSEventStreamStart failed"]
            )
            if let onSetupFailed {
                Task { @MainActor in
                    onSetupFailed(error)
                }
            }
            return
        }
        stream = streamRef
    }

    deinit {
        cancel()
    }

    func cancel() {
        debounceTask?.cancel()
        debounceTask = nil
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            stream = nil
        }
    }

    private func scheduleDebounced() {
        debounceTask?.cancel()
        let debounceNs = debounceNanoseconds
        let handler = onEvent
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            handler()
        }
    }

    internal func handleFSEvent() {
        scheduleDebounced()
    }

    private static let fsCallback: FSEventStreamCallback = { _, clientCallBackInfo, _, _, _, _ in
        guard let raw = clientCallBackInfo else { return }
        let watcher = Unmanaged<VaultDirectoryWatcher>.fromOpaque(raw).takeUnretainedValue()
        watcher.handleFSEvent()
    }
}
