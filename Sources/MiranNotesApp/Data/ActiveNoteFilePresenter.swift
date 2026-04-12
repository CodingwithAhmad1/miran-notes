import AppKit
import Foundation

/// `NSFilePresenter` for the active note’s `.txt` only; complements subtree `VaultDirectoryWatcher` with presenter-driven updates while the file is open.
final class ActiveNoteFilePresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue.main
    private let onChange: () -> Void

    init(fileURL: URL, onChange: @escaping () -> Void) {
        self.presentedItemURL = fileURL
        self.onChange = onChange
    }

    func start() {
        NSFileCoordinator.addFilePresenter(self)
    }

    func stop() {
        NSFileCoordinator.removeFilePresenter(self)
    }

    func presentedItemDidChange() {
        onChange()
    }

    func relinquishPresentedItem(toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        writer(nil)
    }
}
