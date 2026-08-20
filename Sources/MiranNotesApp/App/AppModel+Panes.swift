// Pane layout management (split from AppModel.swift; mechanical move).
import AppKit
import Foundation
import MiranNotesCore
import Observation
import os.log
import SwiftUI

extension AppModel {
    // MARK: - Layout management

    /// Switches to a new pane layout. Flushes the active pane, then grows or shrinks ``workspacePanes``.
    func setLayout(_ layout: PaneLayout) {
        Task { @MainActor in
            let newCount = layout.paneCount
            let flushIndex = keyPaneIndex
            await flushPaneIfDirty(flushIndex)
            activePaneIndex = min(max(0, activePaneIndex), max(0, newCount - 1))
            if workspacePanes.count < newCount {
                while workspacePanes.count < newCount {
                    workspacePanes.append(WorkspacePaneSession())
                }
            } else if workspacePanes.count > newCount {
                workspacePanes = Array(workspacePanes.prefix(newCount))
            }
            currentLayout = layout
            undoManager?.removeAllActions(withTarget: self)
            reregisterAllUndoActions(forPane: activePaneIndex)
            updateActiveNoteFilePresenter()
        }
    }

    /// Makes `index` the pane that receives toolbar/search/primary undo registration. Each tile keeps its own navigation state.
    func activatePane(index: Int) {
        guard index != activePaneIndex, index < currentLayout.paneCount else { return }
        Task { await activatePaneAwaitable(index: index) }
    }

    /// Switches the key pane immediately so a synchronous ``apply`` runs against the correct buffer; previous pane flush runs in the background.
    func activatePaneForEditingSync(_ index: Int) {
        guard index != activePaneIndex, index < currentLayout.paneCount else { return }
        let previous = activePaneIndex
        Task { await flushPaneIfDirty(previous) }
        undoManager?.removeAllActions(withTarget: self)
        activePaneIndex = index
        reregisterAllUndoActions(forPane: index)
        updateActiveNoteFilePresenter()
    }

    /// Awaitable activation (e.g. before applying edits so ``apply`` targets the key pane).
    func activatePaneAwaitable(index: Int) async {
        guard index != activePaneIndex, index < currentLayout.paneCount else { return }
        let previous = activePaneIndex
        await flushPaneIfDirty(previous)
        undoManager?.removeAllActions(withTarget: self)
        activePaneIndex = index
        reregisterAllUndoActions(forPane: index)
        updateActiveNoteFilePresenter()
    }
}
