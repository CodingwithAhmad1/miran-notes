import SwiftUI
import MiranNotesCore

struct DatabaseBoardView: View {
    let schema: DatabaseSchema
    let rows: [TableRowRecord]
    let groupByColumnID: String
    let onCellEdit: (UUID, String, String) -> Void
    let onDeleteRow: (UUID) -> Void

    private var groups: [(label: String, rows: [TableRowRecord])] {
        let col = schema.column(id: groupByColumnID)
        let options = col?.options ?? []

        var grouped: [String: [TableRowRecord]] = [:]
        for opt in options { grouped[opt] = [] }
        grouped["Uncategorized"] = []

        for row in rows {
            let val = row.cells[groupByColumnID] ?? ""
            if val.isEmpty {
                grouped["Uncategorized", default: []].append(row)
            } else {
                grouped[val, default: []].append(row)
            }
        }

        var result: [(String, [TableRowRecord])] = []
        for opt in options {
            result.append((opt, grouped[opt] ?? []))
        }
        let uncategorized = grouped["Uncategorized"] ?? []
        if !uncategorized.isEmpty {
            result.append(("Uncategorized", uncategorized))
        }
        return result
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(groups, id: \.label) { group in
                    boardColumn(label: group.label, rows: group.rows)
                }
            }
            .padding()
        }
    }

    private func boardColumn(label: String, rows: [TableRowRecord]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label.capitalized)
                    .font(.caption.weight(.semibold))
                Text("\(rows.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }

            if rows.isEmpty {
                Text("Empty")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(rows, id: \.id) { row in
                    boardCard(row)
                }
            }
        }
        .frame(width: 220)
        .padding(10)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func boardCard(_ row: TableRowRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.cells["title"] ?? row.cells[schema.columns.first?.id ?? ""] ?? "Untitled")
                .font(.callout)
                .lineLimit(2)

            HStack(spacing: 4) {
                ForEach(schema.columns.prefix(3).filter { $0.id != groupByColumnID && $0.id != "title" }, id: \.id) { col in
                    let val = row.cells[col.id] ?? ""
                    if !val.isEmpty {
                        Text(val)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .contextMenu {
            Button("Delete", role: .destructive) { onDeleteRow(row.id) }
        }
    }
}
