import MiranNotesCore
import SwiftUI

struct TableEditorSheet: View {
    let jsonlURL: URL
    let schemaURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var schema: TableSchemaRecord = TableSchemaRecord(columns: [])
    @State private var rows: [TableRowRecord] = []
    @State private var document: TableDocument?
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView("Table error", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else if schema.columns.isEmpty && rows.isEmpty && loadError == nil {
                    ProgressView()
                } else {
                    scrollTable
                }
            }
            .navigationTitle("Table")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        Task {
                            do {
                                try await document?.flushNow()
                                dismiss()
                            } catch {
                                loadError = "Could not save table: \(error.localizedDescription)"
                            }
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            do {
                                let newRow = TableRowRecord()
                                try await document?.appendRow(newRow)
                                if let doc = document {
                                    rows = (await doc.snapshot()).rows
                                }
                            } catch {
                                loadError = "Could not append row: \(error.localizedDescription)"
                            }
                        }
                    } label: {
                        Label("Add row", systemImage: "plus")
                    }
                }
            }
            .task {
                let doc = TableDocument(jsonlURL: jsonlURL, schemaURL: schemaURL)
                document = doc
                do {
                    try await doc.loadIfNeeded()
                    let snap = await doc.snapshot()
                    schema = snap.schema
                    rows = snap.rows
                } catch {
                    loadError = error.localizedDescription
                }
            }
        }
        .frame(minWidth: 480, minHeight: 320)
    }

    private var scrollTable: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ForEach(schema.columns, id: \.id) { col in
                        Text(col.title)
                            .font(.caption.weight(.semibold))
                            .frame(minWidth: 120, alignment: .leading)
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.element.id) { _, row in
                    HStack(alignment: .firstTextBaseline) {
                        ForEach(schema.columns, id: \.id) { col in
                            TextField(
                                col.title,
                                text: Binding(
                                    get: {
                                        rows.first(where: { $0.id == row.id })?.cells[col.id] ?? ""
                                    },
                                    set: { newValue in
                                        Task {
                                            do {
                                                try await document?.updateCell(rowId: row.id, columnId: col.id, value: newValue)
                                                if let doc = document {
                                                    rows = (await doc.snapshot()).rows
                                                }
                                            } catch {
                                                loadError = "Could not update table cell: \(error.localizedDescription)"
                                            }
                                        }
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 120)
                        }
                    }
                }
            }
            .padding()
        }
    }
}
