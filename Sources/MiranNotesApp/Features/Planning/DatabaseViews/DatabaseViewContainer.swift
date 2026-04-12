import SwiftUI
import MiranNotesCore

/// Hosts a database in any of its configured view layouts (table, board, calendar, list).
struct DatabaseViewContainer: View {
    @ObservedObject var model: PlanningModel
    let databaseID: UUID
    @State private var schema: DatabaseSchema = DatabaseSchema()
    @State private var rows: [TableRowRecord] = []
    @State private var views: [DatabaseViewConfig] = []
    @State private var activeViewIndex: Int = 0
    @State private var isLoading = true

    private var activeView: DatabaseViewConfig? {
        guard views.indices.contains(activeViewIndex) else { return nil }
        return views[activeViewIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading database...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                viewPicker
                Divider()
                contentView
            }
        }
        .task { await loadData() }
    }

    private var viewPicker: some View {
        HStack {
            ForEach(Array(views.enumerated()), id: \.element.id) { index, view in
                Button {
                    activeViewIndex = index
                    Task { await refresh() }
                } label: {
                    HStack(spacing: 4) {
                        viewIcon(view.layout)
                        Text(view.name)
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(activeViewIndex == index ? Color.accentColor.opacity(0.12) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var contentView: some View {
        if let view = activeView {
            switch view.layout {
            case .table, .list:
                DatabaseTableView(
                    schema: schema,
                    rows: rows,
                    onCellEdit: { rowID, colID, val in
                        Task { await editCell(rowID: rowID, columnID: colID, value: val) }
                    },
                    onDeleteRow: { rowID in
                        Task { await deleteRow(rowID: rowID) }
                    }
                )
            case .board:
                let groupCol = view.groupByColumnID ?? schema.columns.first(where: { $0.type == .select })?.id ?? ""
                DatabaseBoardView(
                    schema: schema,
                    rows: rows,
                    groupByColumnID: groupCol,
                    onCellEdit: { rowID, colID, val in
                        Task { await editCell(rowID: rowID, columnID: colID, value: val) }
                    },
                    onDeleteRow: { rowID in
                        Task { await deleteRow(rowID: rowID) }
                    }
                )
            case .calendar:
                Text("Calendar view for \(view.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            Text("No views configured")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func viewIcon(_ layout: DatabaseViewLayout) -> some View {
        let name: String = switch layout {
        case .table: "tablecells"
        case .board: "rectangle.split.3x1"
        case .calendar: "calendar"
        case .list: "list.bullet"
        }
        return Image(systemName: name).font(.caption2)
    }

    private func loadData() async {
        do {
            let repo = model.databaseRepo
            let doc = try await repo.openDocument(id: databaseID)
            try await doc.loadIfNeeded()
            let snapshot = await doc.snapshot()
            schema = snapshot.schema
            views = snapshot.views
            if let view = activeView {
                rows = await doc.filteredRows(view: view)
            } else {
                rows = snapshot.rows
            }
            isLoading = false
        } catch {
            isLoading = false
        }
    }

    private func refresh() async {
        do {
            let repo = model.databaseRepo
            let doc = try await repo.openDocument(id: databaseID)
            if let view = activeView {
                rows = await doc.filteredRows(view: view)
            } else {
                rows = await doc.allRows()
            }
        } catch {}
    }

    private func editCell(rowID: UUID, columnID: String, value: String) async {
        do {
            let repo = model.databaseRepo
            let doc = try await repo.openDocument(id: databaseID)
            await doc.updateCell(rowID: rowID, columnID: columnID, value: value)
            try await doc.flushToDisk()
            await refresh()
        } catch {}
    }

    private func deleteRow(rowID: UUID) async {
        do {
            let repo = model.databaseRepo
            let doc = try await repo.openDocument(id: databaseID)
            await doc.deleteRow(id: rowID)
            try await doc.flushToDisk()
            await refresh()
        } catch {}
    }
}

extension PlanningModel {
    var databaseRepo: DatabaseRepository {
        _databaseRepo
    }
}
