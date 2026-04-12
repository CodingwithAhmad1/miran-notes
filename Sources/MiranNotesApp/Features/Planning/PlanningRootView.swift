import SwiftUI
import MiranNotesCore

enum PlanningTab: String, CaseIterable {
    case dashboard = "Dashboard"
    case calendar = "Calendar"
    case tasks = "Tasks"
    case sessions = "Sessions"
    case settings = "Settings"
}

struct PlanningRootView: View {
    @ObservedObject var model: PlanningModel
    @State private var activeTab: PlanningTab = .dashboard

    var body: some View {
        NavigationSplitView {
            planningSidebar
                .navigationTitle("Planning")
        } detail: {
            detailView
        }
    }

    private var planningSidebar: some View {
        List(selection: $activeTab) {
            Section("Views") {
                Label("Dashboard", systemImage: "house")
                    .tag(PlanningTab.dashboard)
                Label("Calendar", systemImage: "calendar")
                    .tag(PlanningTab.calendar)
            }

            Section("Databases") {
                Label("Tasks", systemImage: "checklist")
                    .tag(PlanningTab.tasks)
                Label("Sessions", systemImage: "clock.arrow.circlepath")
                    .tag(PlanningTab.sessions)
            }

            Section {
                Label("Settings", systemImage: "gearshape")
                    .tag(PlanningTab.settings)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detailView: some View {
        switch activeTab {
        case .dashboard:
            PlanningDashboardView(model: model)
        case .calendar:
            CalendarContainerView(model: model)
        case .tasks:
            TasksDatabaseView(model: model)
        case .sessions:
            SessionsDatabaseView(model: model)
        case .settings:
            PlanningSettingsView(model: model)
        }
    }
}

private struct TasksDatabaseView: View {
    @ObservedObject var model: PlanningModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tasks Database")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    Task { await model.refreshTasks() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
            Divider()

            DatabaseTableView(
                schema: PlanningSchemas.tasksSchema(),
                rows: model.allTasks,
                onCellEdit: { rowID, colID, value in
                    Task {
                        let currentRow = model.allTasks.first(where: { $0.id == rowID })
                        var cells = currentRow?.cells ?? [:]
                        cells[colID] = value
                        await model.updateTask(rowID: rowID, cells: cells)
                    }
                },
                onDeleteRow: { rowID in
                    Task { await model.deleteTask(rowID: rowID) }
                }
            )
        }
    }
}

private struct SessionsDatabaseView: View {
    @ObservedObject var model: PlanningModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sessions Database")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    Task { await model.refreshSessions() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
            Divider()

            DatabaseTableView(
                schema: PlanningSchemas.sessionsSchema(),
                rows: model.allSessions,
                onCellEdit: { rowID, colID, value in
                    Task {
                        let currentRow = model.allSessions.first(where: { $0.id == rowID })
                        var cells = currentRow?.cells ?? [:]
                        cells[colID] = value
                        await model.updateTask(rowID: rowID, cells: cells)
                    }
                },
                onDeleteRow: { rowID in
                    Task { await model.deleteSession(rowID: rowID) }
                }
            )
        }
    }
}
