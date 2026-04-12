import Darwin
import Dispatch
import Foundation

/// Watches a directory with `O_EVTONLY` + `DispatchSource` (Phase 5: replace polling).
/// Fires `onEvent` on the main queue when the filesystem reports activity; debounce coalesces bursts.
final class VaultDirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let debounceNanoseconds: UInt64
    private var debounceTask: Task<Void, Never>?
    private let onEvent: @MainActor () -> Void

    init(
        vaultURL: URL,
        debounceMilliseconds: UInt64 = 150,
        onSetupFailed: (@MainActor (Error) -> Void)? = nil,
        onEvent: @escaping @MainActor () -> Void
    ) {
        self.debounceNanoseconds = debounceMilliseconds * 1_000_000
        self.onEvent = onEvent

        fileDescriptor = open(vaultURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            let code = errno
            let message = String(cString: strerror(code))
            let error = NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(code),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
            if let onSetupFailed {
                Task { @MainActor in
                    onSetupFailed(error)
                }
            }
            return
        }

        let queue = DispatchQueue.main
        let mask: DispatchSource.FileSystemEvent = [.write, .rename, .extend, .attrib, .link, .revoke, .delete]
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: mask,
            queue: queue
        )
        src.setEventHandler { [weak self] in
            self?.scheduleDebounced()
        }
        src.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        src.resume()
        source = src
    }

    deinit {
        cancel()
    }

    /// Stops listening; the dispatch source’s cancel handler closes the `O_EVTONLY` descriptor.
    func cancel() {
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()
        source = nil
    }

    private func scheduleDebounced() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            onEvent()
        }
    }
}
