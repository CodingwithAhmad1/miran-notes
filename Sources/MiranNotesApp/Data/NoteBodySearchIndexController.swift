import Foundation
import os.log

/// Owns the async rebuild of the vault body-text map used for sidebar search snippets.
@MainActor
final class NoteBodySearchIndexController {
    private var rebuildTask: Task<Void, Never>?
    private var generation = 0

    func cancel() {
        rebuildTask?.cancel()
        rebuildTask = nil
    }

    /// Cancels any in-flight build, bumps generation, and starts `NoteRepository/buildSearchIndexes()`.
    func scheduleRebuild(
        repository: NoteRepository,
        apply: @escaping @MainActor (VaultSearchIndexes) -> Void,
        onFailure: @escaping @MainActor () -> Void
    ) {
        rebuildTask?.cancel()
        generation += 1
        let gen = generation
        rebuildTask = Task {
            let index: VaultSearchIndexes
            do {
                index = try await repository.buildSearchIndexes()
            } catch {
                if error is CancellationError { return }
                await MainActor.run {
                    Logger.vault.error(
                        "buildSearchIndexes failed: \(error.localizedDescription, privacy: .public)"
                    )
                    onFailure()
                }
                return
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard gen == self.generation else { return }
                apply(index)
            }
        }
    }
}
