// File → Export: Markdown and PDF of the active note.
import AppKit
import Foundation
import MiranNotesCore

extension AppModel {
    /// Markdown source for the active note: `.md` bodies export as-is, block notes convert.
    func exportMarkdownText(pane: Int? = nil) -> String? {
        let pane = pane ?? activePaneIndex
        guard workspacePanes.indices.contains(pane), let doc = workspacePanes[pane].activeDocument else { return nil }
        if resolvedBodyFileExtensionForSelectedNote(pane: pane) == "md" {
            return doc.text
        }
        return NoteMarkdownExporter.markdown(for: doc)
    }

    /// Renders the active note to PDF data using the editor's own visual styling.
    func exportPDFData(pane: Int? = nil) -> Data? {
        let pane = pane ?? activePaneIndex
        guard workspacePanes.indices.contains(pane), let doc = workspacePanes[pane].activeDocument else { return nil }

        let pageWidth: CGFloat = 612  // US Letter width in points
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: 100))
        textView.textContainerInset = NSSize(width: 36, height: 36)
        textView.string = doc.text
        EditorVisualStyle.apply(to: textView, document: doc)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let used = textView.layoutManager?.usedRect(for: textView.textContainer!) ?? .zero
        let height = max(200, used.height + 96)
        textView.frame = NSRect(x: 0, y: 0, width: pageWidth, height: height)
        return textView.dataWithPDF(inside: textView.bounds)
    }

    func presentExportPanel(kind: NoteExportKind, pane: Int? = nil) {
        let pane = pane ?? activePaneIndex
        guard workspacePanes.indices.contains(pane), workspacePanes[pane].activeDocument != nil else { return }
        let baseName = selectedNoteHeaderTitle(forPane: pane)
        let suggested = baseName.isEmpty ? "note" : baseName

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(suggested).\(kind.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch kind {
            case .markdown:
                guard let text = exportMarkdownText(pane: pane) else { return }
                try text.write(to: url, atomically: true, encoding: .utf8)
            case .pdf:
                guard let data = exportPDFData(pane: pane) else { return }
                try data.write(to: url, options: .atomic)
            }
        } catch {
            userAlert = .message("Export failed: \(error.localizedDescription)")
        }
    }
}

enum NoteExportKind {
    case markdown
    case pdf

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .pdf: "pdf"
        }
    }
}
