// Attachments: copy files into `_aux/<noteID>/attachments/` and reference them with
// `[attachment: name]` text tokens (inserted through the normal replaceText pipeline).
import AppKit
import Foundation
import MiranNotesCore

extension AppModel {
    var attachmentStore: NoteAttachmentStore {
        NoteAttachmentStore(vaultURL: repository.vaultURL)
    }

    /// Copies files in and inserts their tokens at `utf16Offset` (defaults to the caret).
    func attachFiles(_ urls: [URL], pane: Int? = nil, atUTF16Offset offset: Int? = nil) {
        let pane = pane ?? activePaneIndex
        guard workspacePanes.indices.contains(pane), let doc = workspacePanes[pane].activeDocument else { return }
        var storedNames: [String] = []
        for url in urls {
            do {
                storedNames.append(try attachmentStore.copyIn(fileAt: url, noteID: doc.metadata.noteID))
            } catch {
                userAlert = .message("Could not attach \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        guard !storedNames.isEmpty else { return }

        let docLength = (doc.text as NSString).length
        let insertAt = min(max(0, offset ?? workspacePanes[pane].editorTextSelection.start), docLength)
        let tokenText = storedNames.map { AttachmentTokenScanner.tokenText(filename: $0) }.joined(separator: " ")
        if pane != activePaneIndex { activatePaneForEditingSync(pane) }
        _ = apply([.replaceText(range: TextRange(start: insertAt, length: 0), replacement: tokenText)])
    }

    func presentAttachFilePanel(pane: Int? = nil) {
        let pane = pane ?? activePaneIndex
        guard workspacePanes.indices.contains(pane), workspacePanes[pane].activeDocument != nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Attach"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        attachFiles(panel.urls, pane: pane)
    }

    /// Opens a clicked attachment token with the system default app; missing files alert.
    func openAttachment(filename: String, pane: Int? = nil) {
        let pane = pane ?? activePaneIndex
        guard workspacePanes.indices.contains(pane), let doc = workspacePanes[pane].activeDocument else { return }
        let noteID = doc.metadata.noteID
        guard attachmentStore.exists(noteID: noteID, filename: filename) else {
            userAlert = .message("Attachment “\(filename)” is missing from this note’s attachments folder.")
            return
        }
        NSWorkspace.shared.open(attachmentStore.fileURL(noteID: noteID, filename: filename))
    }
}
