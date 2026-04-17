import AppKit
import SwiftUI

struct WorkspaceFolderSidebarView: View {
    @Bindable var model: AppModel
    /// Index of the workspace tile this sidebar belongs to.
    var paneIndex: Int = 0
    var onClearToolbarSearchFocus: () -> Void = {}
    @State private var renamingFolder: FolderEntry?
    @State private var renameFieldText = ""

    var body: some View {
        GeometryReader { geometry in
            let safeBottom = geometry.safeAreaInsets.bottom
            let heights = Self.partitionListAndFooterHeights(
                totalHeight: geometry.size.height,
                sidebarWidth: geometry.size.width,
                footerSafeBottomInset: safeBottom
            )

            VStack(spacing: 0) {
                // Sidebar `List` is backed by AppKit `NSTableView` inside an `NSScrollView`. In sparse lists,
                // that scroll view can paint (and hit-test) through the SwiftUI stack until something forces
                // a relayout. Pinning `masksToBounds` on the enclosing scroll view keeps the table from
                // overlapping the footer below this list.
                List(selection: folderSelection) {
                    if model.showsVaultTrayAsButton {
                        Button {
                            onClearToolbarSearchFocus()
                            model.activatePane(index: paneIndex)
                            model.selectFolderForPage(model.sidebarNotesTrayFolderID, pane: paneIndex)
                        } label: {
                            Label(model.sidebarNotesTrayTitle, systemImage: "tray.full")
                        }
                        .buttonStyle(.plain)
                        .tag(Optional(model.sidebarNotesTrayFolderID))
                    } else {
                        Label(model.sidebarNotesTrayTitle, systemImage: "tray.full")
                            .tag(Optional(model.sidebarNotesTrayFolderID))
                    }
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
                .frame(width: geometry.size.width, height: heights.list, alignment: .top)
                .clipped()
                .overlay {
                    ListEnclosingScrollViewClip()
                        .allowsHitTesting(false)
                }

                sidebarFooterChrome(
                    width: geometry.size.width,
                    footerHeight: heights.footer,
                    safeBottomInset: safeBottom
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
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
            get: { model.workspacePanes[paneIndex].selectedFolderID },
            set: { newID in
                model.activatePane(index: paneIndex)
                model.selectFolderForPage(newID, pane: paneIndex)
            }
        )
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )
    }

    @ViewBuilder
    private func sidebarFooterChrome(width: CGFloat, footerHeight: CGFloat, safeBottomInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            sidebarActionsFooter
            workspaceLocationFooter
            if safeBottomInset > 0.5 {
                Color.clear.frame(height: safeBottomInset)
            }
        }
        .frame(width: width, height: footerHeight, alignment: .topLeading)
    }

    private var sidebarActionsFooter: some View {
        HStack(spacing: 6) {
            Text("Miran Notes")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button {
                onClearToolbarSearchFocus()
                model.activatePane(index: paneIndex)
                model.createFolder(pane: paneIndex)
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.plain)
            .help("New Folder")

            Button {
                onClearToolbarSearchFocus()
                model.activatePane(index: paneIndex)
                model.createNote(pane: paneIndex)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .disabled(!model.allowsToolbarNewNote(forPane: paneIndex))
            .help(
                model.allowsToolbarNewNote(forPane: paneIndex)
                    ? "New Note"
                    : "Select a folder (not Vault) to create a note"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 2)
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
        .padding(.top, 2)
        .padding(.bottom, 8)
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

    /// Non-scrolling footer band; grows slightly on narrow sidebars if the path may wrap.
    private static func footerChromeHeight(forSidebarWidth width: CGFloat) -> CGFloat {
        let base: CGFloat = 108
        guard width.isFinite, width > 0, width < 210 else { return base }
        return base + 18
    }

    private static let minListHeight: CGFloat = 72

    private static func partitionListAndFooterHeights(
        totalHeight: CGFloat,
        sidebarWidth: CGFloat,
        footerSafeBottomInset: CGFloat = 0
    ) -> (list: CGFloat, footer: CGFloat) {
        let desiredFooter =
            footerChromeHeight(forSidebarWidth: sidebarWidth) + max(0, footerSafeBottomInset)
        let listMin = minListHeight
        let footerMin: CGFloat = 56
        guard totalHeight.isFinite, totalHeight > 1 else {
            return (listMin, desiredFooter)
        }
        if totalHeight >= desiredFooter + listMin {
            let footer = desiredFooter
            return (totalHeight - footer, footer)
        }
        if totalHeight >= listMin + footerMin {
            let list = listMin
            return (list, totalHeight - list)
        }
        let footer = min(footerMin, totalHeight)
        return (max(0, totalHeight - footer), footer)
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
    /// Clips every enclosing `NSScrollView` up to the window. With a very short sidebar list, the first
    /// scroll view in the hierarchy is not always the `NSTableView` host; clipping only that view can miss
    /// the view that still paints through the footer.
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
        ListScrollViewClip.applyEnclosingScrollViewClipping(anchor: nsView)
        DispatchQueue.main.async {
            ListScrollViewClip.applyEnclosingScrollViewClipping(anchor: nsView)
        }
    }
}
