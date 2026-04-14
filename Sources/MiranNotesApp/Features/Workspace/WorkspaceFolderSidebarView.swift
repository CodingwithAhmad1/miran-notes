import AppKit
import SwiftUI

struct WorkspaceFolderSidebarView: View {
    @Bindable var model: AppModel
    var onClearToolbarSearchFocus: () -> Void = {}
    @State private var renamingFolder: FolderEntry?
    @State private var renameFieldText = ""

    var body: some View {
        // Sidebar `List` is backed by AppKit `NSTableView` inside an `NSScrollView`. In sparse lists,
        // that scroll view can paint (and hit-test) through the SwiftUI stack until something forces
        // a relayout (e.g. toggling Folder Management / the unified toolbar). Pinning `masksToBounds`
        // on the enclosing scroll view keeps the table from swallowing the footer below this list.
        VStack(spacing: 0) {
            List(selection: folderSelection) {
                Label(model.sidebarNotesTrayTitle, systemImage: "tray.full")
                    .tag(Optional(model.sidebarNotesTrayFolderID))
                ForEach(model.visibleTopLevelFolderEntries, id: \.id) { folder in
                    Text(folder.name)
                        .tag(Optional(folder.id))
                        .contextMenu {
                            Button("Rename…") {
                                renamingFolder = folder
                                renameFieldText = folder.name
                            }
                            Button("Delete Folder", role: .destructive) {
                                model.deleteFolder(id: folder.id)
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                ListEnclosingScrollViewClip()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                Divider()
                sidebarActionsFooter
                workspaceLocationFooter
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .simultaneousGesture(
            TapGesture().onEnded { _ in
                onClearToolbarSearchFocus()
            }
        )
        .navigationTitle("Vault")
        .alert("Rename Folder", isPresented: renameBinding, presenting: renamingFolder) { folder in
            TextField("Name", text: $renameFieldText)
            Button("Cancel", role: .cancel) {
                renamingFolder = nil
            }
            Button("OK") {
                let trimmed = renameFieldText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    model.renameFolder(id: folder.id, newName: trimmed)
                }
                renamingFolder = nil
            }
        } message: { _ in
            Text("Enter a new name for this folder.")
        }
    }

    private var folderSelection: Binding<UUID?> {
        Binding(
            get: { model.selectedFolderID },
            set: { model.selectFolderForPage($0) }
        )
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )
    }

    private var sidebarActionsFooter: some View {
        HStack(spacing: 6) {
            Text("Miran Notes")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button {
                onClearToolbarSearchFocus()
                model.createFolder()
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.plain)
            .help("New Folder")

            Button {
                onClearToolbarSearchFocus()
                model.createNote()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .disabled(!model.allowsToolbarNewNote)
            .help(
                model.allowsToolbarNewNote
                    ? "New Note"
                    : "Select a folder (not Vault) to create a note"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var workspaceLocationFooter: some View {
        let path = model.repository.vaultURL.path
        return VStack(alignment: .leading, spacing: 2) {
            Text(Self.truncatedPath(path, maxCharacters: 52))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(path)
            Text("Open Workspace… — Shift-Command-O")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    /// Middle ellipsis when the path is long; keeps start and end visible for Finder-style paths.
    private static func truncatedPath(_ path: String, maxCharacters: Int) -> String {
        guard path.count > maxCharacters else { return path }
        let budget = max(3, maxCharacters - 1)
        let head = budget / 2
        let tail = budget - head
        let s = path.startIndex
        let e = path.endIndex
        guard let headEnd = path.index(s, offsetBy: head, limitedBy: e),
            let tailStart = path.index(e, offsetBy: -tail, limitedBy: s),
            headEnd < tailStart
        else {
            return String(path.prefix(max(0, budget - 2))) + "…"
        }
        return String(path[s..<headEnd]) + "…" + String(path[tailStart..<e])
    }
}

// MARK: - AppKit clip fix (SwiftUI List / NSTableView)

private final class ListClipAnchorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        MainActor.assumeIsolated {
            ListScrollViewClip.applyEnclosingScrollViewClipping(anchor: self)
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        MainActor.assumeIsolated {
            ListScrollViewClip.applyEnclosingScrollViewClipping(anchor: self)
        }
    }

    override func layout() {
        super.layout()
        MainActor.assumeIsolated {
            ListScrollViewClip.applyEnclosingScrollViewClipping(anchor: self)
        }
    }
}

@MainActor
private enum ListScrollViewClip {
    static func applyEnclosingScrollViewClipping(anchor: NSView) {
        var current: NSView? = anchor
        while let view = current {
            if let scroll = view as? NSScrollView {
                scroll.clipsToBounds = true
                scroll.wantsLayer = true
                scroll.layer?.masksToBounds = true
                let clipView = scroll.contentView
                clipView.wantsLayer = true
                clipView.layer?.masksToBounds = true
                return
            }
            current = view.superview
        }
    }
}

private struct ListEnclosingScrollViewClip: NSViewRepresentable {
    func makeNSView(context: Context) -> ListClipAnchorView {
        ListClipAnchorView()
    }

    func updateNSView(_ nsView: ListClipAnchorView, context: Context) {
        Task { @MainActor in
            ListScrollViewClip.applyEnclosingScrollViewClipping(anchor: nsView)
        }
    }
}
