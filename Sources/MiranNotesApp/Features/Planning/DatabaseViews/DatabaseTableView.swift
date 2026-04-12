import SwiftUI
import MiranNotesCore

struct DatabaseTableView: View {
    let schema: DatabaseSchema
    let rows: [TableRowRecord]
    let onCellEdit: (UUID, String, String) -> Void
    let onDeleteRow: (UUID) -> Void

    @State private var editingCell: CellID?
    @State private var editValue = ""

    private struct CellID: Hashable {
        let rowID: UUID
        let columnID: String
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                Divider()
                ForEach(rows, id: \.id) { row in
                    dataRow(row)
                    Divider()
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(schema.columns, id: \.id) { col in
                Text(col.title)
                    .font(.caption.weight(.semibold))
                    .frame(width: columnWidth(col), alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
            }
        }
        .background(.quaternary.opacity(0.5))
    }

    private func dataRow(_ row: TableRowRecord) -> some View {
        HStack(spacing: 0) {
            ForEach(schema.columns, id: \.id) { col in
                let cellID = CellID(rowID: row.id, columnID: col.id)
                let value = row.cells[col.id] ?? ""

                if editingCell == cellID {
                    TextField("", text: $editValue, onCommit: {
                        onCellEdit(row.id, col.id, editValue)
                        editingCell = nil
                    })
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .frame(width: columnWidth(col), alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                } else {
                    cellView(value: value, column: col)
                        .frame(width: columnWidth(col), alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editValue = value
                            editingCell = cellID
                        }
                }
            }
        }
        .contextMenu {
            Button("Delete Row", role: .destructive) {
                onDeleteRow(row.id)
            }
        }
    }

    @ViewBuilder
    private func cellView(value: String, column: DatabaseColumnDefinition) -> some View {
        switch column.type {
        case .boolean:
            Image(systemName: value.lowercased() == "true" ? "checkmark.square.fill" : "square")
                .foregroundStyle(value.lowercased() == "true" ? .green : .secondary)
                .font(.caption)
        case .select:
            if !value.isEmpty {
                Text(value)
                    .font(.caption)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary)
                    .clipShape(Capsule())
            } else {
                Text("-")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        default:
            Text(value.isEmpty ? "-" : value)
                .font(.caption)
                .foregroundStyle(value.isEmpty ? .tertiary : .primary)
                .lineLimit(1)
        }
    }

    private func columnWidth(_ col: DatabaseColumnDefinition) -> CGFloat {
        switch col.type {
        case .boolean: return 50
        case .date: return 100
        case .number, .duration: return 70
        case .select: return 100
        default: return 150
        }
    }
}
