import SwiftUI

/// One item on the browser canvas.
enum FolderBrowserItem: Identifiable, Equatable {
    case folder(FolderEntry)
    case note(NoteSummary)

    var id: UUID {
        switch self {
        case .folder(let f): f.id
        case .note(let n): n.noteID
        }
    }

    var title: String {
        switch self {
        case .folder(let f): f.name
        case .note(let n): n.title
        }
    }
}

/// Finder-style icon canvas for a folder page: icons sit where the user left them
/// (persisted per folder under `.miran/ui-state/icon-layout/`), unplaced items auto-flow
/// into a grid. Double-click opens; drag repositions (8-pt snap); dropping a note on a
/// repository-folder icon moves it there; "Clean Up" re-flows everything.
struct FolderIconBrowserView: View {
    @Bindable var model: AppModel
    var paneIndex: Int
    /// Folder whose contents are shown (vault root for the notes tray).
    let folderID: UUID
    let items: [FolderBrowserItem]

    @State private var selectedItemID: UUID?
    @State private var draggingItemID: UUID?
    @State private var dragTranslation: CGSize = .zero
    @State private var dropTargetID: UUID?

    private static let cellSize = CGSize(width: 112, height: 104)
    private static let iconSnap: CGFloat = 8
    private static let canvasPadding: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let layout = resolvedPositions(availableWidth: geometry.size.width)
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Background: click clears selection; context menu offers Clean Up.
                    Color.clear
                        .frame(
                            width: max(geometry.size.width, 1),
                            height: max(contentHeight(layout: layout), geometry.size.height)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selectedItemID = nil }
                        .contextMenu {
                            Button("Clean Up") {
                                model.clearIconLayout(folderID: folderID)
                            }
                        }

                    ForEach(items) { item in
                        iconView(item, layout: layout)
                    }
                }
            }
        }
    }

    // MARK: - Layout

    /// Stored positions where present; everything else flows into grid slots left-to-right.
    private func resolvedPositions(availableWidth: CGFloat) -> [UUID: CGPoint] {
        let stored = model.iconPositions(folderID: folderID)
        var resolved: [UUID: CGPoint] = [:]
        let columns = max(1, Int((max(availableWidth, Self.cellSize.width) - Self.canvasPadding * 2) / Self.cellSize.width))
        var nextSlot = 0
        let occupied = Set(stored.filter { position in items.contains(where: { $0.id == position.key }) }.map(\.key))
        for item in items {
            if let point = stored[item.id] {
                resolved[item.id] = point
            } else {
                // Find the next free grid slot (skip slots that collide with a stored position).
                var placed = false
                while !placed {
                    let slotPoint = gridPoint(slot: nextSlot, columns: columns)
                    nextSlot += 1
                    let collides = occupied.contains { id in
                        guard let p = stored[id] else { return false }
                        return abs(p.x - slotPoint.x) < Self.cellSize.width * 0.6
                            && abs(p.y - slotPoint.y) < Self.cellSize.height * 0.6
                    }
                    if !collides {
                        resolved[item.id] = slotPoint
                        placed = true
                    }
                }
            }
        }
        return resolved
    }

    private func gridPoint(slot: Int, columns: Int) -> CGPoint {
        let row = slot / columns
        let column = slot % columns
        return CGPoint(
            x: Self.canvasPadding + CGFloat(column) * Self.cellSize.width,
            y: Self.canvasPadding + CGFloat(row) * Self.cellSize.height
        )
    }

    private func contentHeight(layout: [UUID: CGPoint]) -> CGFloat {
        let maxY = layout.values.map(\.y).max() ?? 0
        return maxY + Self.cellSize.height + Self.canvasPadding
    }

    private func currentPoint(for itemID: UUID, layout: [UUID: CGPoint]) -> CGPoint {
        var point = layout[itemID] ?? CGPoint(x: Self.canvasPadding, y: Self.canvasPadding)
        if draggingItemID == itemID {
            point.x += dragTranslation.width
            point.y += dragTranslation.height
        }
        return point
    }

    // MARK: - Icons

    @ViewBuilder
    private func iconView(_ item: FolderBrowserItem, layout: [UUID: CGPoint]) -> some View {
        let point = currentPoint(for: item.id, layout: layout)
        let isSelected = selectedItemID == item.id
        let isDropTarget = dropTargetID == item.id

        VStack(spacing: 4) {
            Image(systemName: iconSymbol(item))
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(iconColor(item))
                .frame(height: 44)
            Text(item.title)
                .font(.system(size: 11.5))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.accentColor.opacity(0.85) : Color.clear)
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .frame(width: Self.cellSize.width - 12, height: Self.cellSize.height - 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDropTarget ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isDropTarget ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .position(x: point.x + Self.cellSize.width / 2, y: point.y + Self.cellSize.height / 2)
        .zIndex(draggingItemID == item.id ? 1 : 0)
        .onTapGesture(count: 2) { open(item) }
        .simultaneousGesture(
            TapGesture().onEnded { selectedItemID = item.id }
        )
        .contextMenu { contextMenu(item) }
        .gesture(dragGesture(item, layout: layout))
        .help(helpText(item))
    }

    private func iconSymbol(_ item: FolderBrowserItem) -> String {
        switch item {
        case .folder(let f):
            model.folderRole(for: f.id) == .dashboard ? "square.grid.2x2.fill" : "folder.fill"
        case .note:
            "doc.text.fill"
        }
    }

    private func iconColor(_ item: FolderBrowserItem) -> Color {
        switch item {
        case .folder: Color.accentColor.opacity(0.85)
        case .note: Color.secondary.opacity(0.8)
        }
    }

    private func helpText(_ item: FolderBrowserItem) -> String {
        switch item {
        case .folder(let f): model.folderCatalog.relativeDirectoryPath(for: f.id)
        case .note(let n): n.relativePath
        }
    }

    @ViewBuilder
    private func contextMenu(_ item: FolderBrowserItem) -> some View {
        switch item {
        case .note(let summary):
            Button("Open") { open(item) }
            Button(model.isNotePinned(summary.noteID) ? "Unpin Note" : "Pin Note") {
                model.togglePinned(noteID: summary.noteID)
            }
            moveToMenu(summary)
            Divider()
            Button("Delete Note", role: .destructive) {
                model.deleteNoteFromFolder(noteID: summary.noteID)
            }
        case .folder(let folder):
            Button("Open") { open(item) }
            Divider()
            Button("Delete Folder", role: .destructive) {
                model.deleteFolder(id: folder.id)
            }
        }
    }

    @ViewBuilder
    private func moveToMenu(_ summary: NoteSummary) -> some View {
        let destinations = model.moveDestinationFolders(excludingFolderID: summary.folderID)
        if !destinations.isEmpty {
            Menu("Move To") {
                ForEach(destinations, id: \.id) { destination in
                    Button(destination.name) {
                        model.moveNote(noteID: summary.noteID, toFolderID: destination.id)
                    }
                }
            }
        }
    }

    private func open(_ item: FolderBrowserItem) {
        model.activatePane(index: paneIndex)
        switch item {
        case .folder(let f):
            model.selectFolderForPage(f.id, pane: paneIndex)
        case .note(let n):
            model.openNote(noteID: n.noteID, pane: paneIndex)
        }
    }

    // MARK: - Dragging

    private func dragGesture(_ item: FolderBrowserItem, layout: [UUID: CGPoint]) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                draggingItemID = item.id
                dragTranslation = value.translation
                dropTargetID = dropTarget(for: item, at: dropPoint(item, layout: layout), layout: layout)?.id
            }
            .onEnded { value in
                dragTranslation = value.translation
                let point = dropPoint(item, layout: layout)
                defer {
                    draggingItemID = nil
                    dragTranslation = .zero
                    dropTargetID = nil
                }
                if let target = dropTarget(for: item, at: point, layout: layout) {
                    performDrop(of: item, onto: target)
                    return
                }
                let snapped = CGPoint(
                    x: max(0, (point.x / Self.iconSnap).rounded() * Self.iconSnap),
                    y: max(0, (point.y / Self.iconSnap).rounded() * Self.iconSnap)
                )
                model.setIconPosition(
                    snapped,
                    itemID: item.id,
                    folderID: folderID,
                    validItemIDs: Set(items.map(\.id))
                )
            }
    }

    /// Dragged icon's top-leading point in canvas space at the current translation.
    private func dropPoint(_ item: FolderBrowserItem, layout: [UUID: CGPoint]) -> CGPoint {
        currentPoint(for: item.id, layout: layout)
    }

    /// Folder icon under the dragged item's center that can accept it, if any.
    private func dropTarget(
        for dragged: FolderBrowserItem,
        at point: CGPoint,
        layout: [UUID: CGPoint]
    ) -> FolderBrowserItem? {
        let center = CGPoint(x: point.x + Self.cellSize.width / 2, y: point.y + Self.cellSize.height / 2)
        for item in items where item.id != dragged.id {
            guard case .folder(let folder) = item, let base = layout[item.id] else { continue }
            let frame = CGRect(origin: base, size: Self.cellSize)
            guard frame.contains(center) else { continue }
            switch dragged {
            case .note:
                return model.folderCatalog.allowsNotes(in: folder.id) ? item : nil
            case .folder:
                return model.folderCatalog.allowsNestedFolders(in: folder.id) ? item : nil
            }
        }
        return nil
    }

    private func performDrop(of dragged: FolderBrowserItem, onto target: FolderBrowserItem) {
        guard case .folder(let destination) = target else { return }
        switch dragged {
        case .note(let summary):
            model.moveNote(noteID: summary.noteID, toFolderID: destination.id)
        case .folder(let folder):
            model.moveFolder(id: folder.id, newParentID: destination.id)
        }
    }
}
