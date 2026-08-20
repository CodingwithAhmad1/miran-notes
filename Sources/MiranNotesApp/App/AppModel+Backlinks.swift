// Backlink refresh and navigation (split from AppModel.swift; mechanical move).
import AppKit
import Foundation
import MiranNotesCore
import Observation
import os.log
import SwiftUI

extension AppModel {
    func refreshBacklinks() async {
        await refreshBacklinks(forPane: activePaneIndex)
    }

    func refreshBacklinks(forPane pane: Int) async {
        guard workspacePanes.indices.contains(pane) else { return }
        guard let doc = workspacePanes[pane].activeDocument else {
            workspacePanes[pane].backlinks = []
            return
        }
        let targetNoteID = doc.metadata.noteID
        do {
            let graph = try await repository.loadLinkGraph()
            let resolver = try await repository.linkResolver()
            let sourceIDs = graph.backlinks(to: targetNoteID)
            var result: [BacklinkItem] = []
            for sid in sourceIDs {
                guard let relPath = resolver.baseName(forTargetNoteID: sid) else { continue }
                let title =
                    noteSummaries.first(where: { $0.noteID == sid })?.title
                    ?? (relPath as NSString).lastPathComponent.replacingOccurrences(of: "-", with: " ").capitalized
                var snippet = ""
                var linkRange = MiranNotesCore.TextRange(start: 0, length: 0)
                if let sourceResult = try? await repository.loadNote(noteID: sid) {
                    let sourceDoc = sourceResult.document
                    if let link = sourceDoc.metadata.links.first(where: { $0.targetNoteID == targetNoteID }) {
                        linkRange = link.range
                        snippet = BacklinkSnippetBuilder.snippet(around: link.range, in: sourceDoc.text)
                    }
                }
                result.append(
                    BacklinkItem(
                        sourceNoteID: sid,
                        title: title,
                        relativePath: relPath,
                        snippet: snippet,
                        linkRange: linkRange
                    )
                )
            }
            workspacePanes[pane].backlinks = result
        } catch {
            workspacePanes[pane].backlinks = []
            userAlert = .recoverable(
                message: "Could not refresh backlinks: \(error.localizedDescription)",
                kind: .retryRefreshBacklinks
            )
        }
    }

    func scheduleBacklinkRefresh(forPane pane: Int) {
        backlinkRefreshScheduler.schedule(delay: .milliseconds(1500)) { [weak self] in
            guard let self else { return }
            await self.refreshBacklinks(forPane: pane)
        }
    }


    func openBacklinkSource(_ item: BacklinkItem, pane: Int? = nil) {
        let p = pane ?? activePaneIndex
        if !item.linkRange.isEmpty {
            pendingEditorScroll = PendingEditorScroll(noteID: item.sourceNoteID, range: item.linkRange)
        } else {
            pendingEditorScroll = nil
        }
        if workspacePanes[p].activeDocument?.metadata.noteID == item.sourceNoteID {
            return
        }
        changeSelection(noteID: item.sourceNoteID, pane: p)
    }

}
