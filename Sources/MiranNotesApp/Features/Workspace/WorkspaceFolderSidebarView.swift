import SwiftUI

struct WorkspaceFolderSidebarView: View {
    @Bindable var model: AppModel
    var onClearToolbarSearchFocus: () -> Void = {}
    @State private var renamingFolder: FolderEntry?
    @State private var renameFieldText = ""

    var body: some View {
        GeometryReader { geometry in
            let heights = Self.partitionListAndFooterHeights(
                totalHeight: geometry.size.height,
                sidebarWidth: geometry.size.width
            )

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
                .frame(width: geometry.size.width, height: heights.list, alignment: .top)
                .clipped()

                sidebarFooterChrome(width: geometry.size.width, footerHeight: heights.footer)
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

    @ViewBuilder
    private func sidebarFooterChrome(width: CGFloat, footerHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            sidebarActionsFooter
            workspaceLocationFooter
        }
        .frame(width: width, height: footerHeight, alignment: .bottomLeading)
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
        .padding(.bottom, 6)
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
        let base: CGFloat = 96
        guard width.isFinite, width > 0, width < 210 else { return base }
        return base + 18
    }

    private static let minListHeight: CGFloat = 72

    private static func partitionListAndFooterHeights(totalHeight: CGFloat, sidebarWidth: CGFloat)
        -> (list: CGFloat, footer: CGFloat)
    {
        let desiredFooter = footerChromeHeight(forSidebarWidth: sidebarWidth)
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
