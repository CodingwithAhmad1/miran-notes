import Foundation
import MiranNotesCore
import os.log

/// Migrates Zora Planning vault data (YAML frontmatter in `.md` files under `.zora/`)
/// into the Miran Notes database layer.
struct ZoraMigrationEngine {
    struct MigrationResult {
        var tasksImported: Int = 0
        var sessionsImported: Int = 0
        var configMigrated: Bool = false
        var errors: [String] = []
    }

    private let zoraRoot: URL
    private let databaseRepo: DatabaseRepository
    private let configManager: PlanningConfigManager
    private let decoder = JSONDecoder()

    init(zoraRoot: URL, databaseRepo: DatabaseRepository, configManager: PlanningConfigManager) {
        self.zoraRoot = zoraRoot
        self.databaseRepo = databaseRepo
        self.configManager = configManager
    }

    func migrate() async throws -> MigrationResult {
        var result = MigrationResult()

        result.configMigrated = await migrateConfig()
        result.tasksImported = await migrateTasks(&result)
        result.sessionsImported = await migrateSessions(&result)

        Logger.vault.info("Zora migration complete: tasks=\(result.tasksImported) sessions=\(result.sessionsImported) errors=\(result.errors.count)")
        return result
    }

    private func migrateConfig() async -> Bool {
        let configURL = zoraRoot.appendingPathComponent("zora-config.json")
        guard let data = try? Data(contentsOf: configURL) else { return false }

        struct ZoraConfig: Decodable {
            var subjects: [String]?
            var colorSchema: [String: String]?
        }

        guard let zoraConfig = try? decoder.decode(ZoraConfig.self, from: data) else { return false }

        var miranConfig = PlanningConfig.default
        if let subjects = zoraConfig.subjects {
            miranConfig.subjects = subjects
        }
        if let colors = zoraConfig.colorSchema {
            miranConfig.colorSchema = colors
        }

        do {
            try await configManager.update(miranConfig)
            return true
        } catch {
            return false
        }
    }

    private func migrateTasks(_ result: inout MigrationResult) async -> Int {
        let tasksDir = zoraRoot.appendingPathComponent("Tasks")
        guard let files = try? FileManager.default.contentsOfDirectory(at: tasksDir, includingPropertiesForKeys: nil) else {
            return 0
        }

        var count = 0
        let tasksDB: DatabaseRegistryRecord?
        do {
            tasksDB = try await databaseRepo.databaseRecord(kind: .tasks)
        } catch {
            result.errors.append("Could not find Tasks database: \(error.localizedDescription)")
            return 0
        }

        guard let dbID = tasksDB?.id else {
            result.errors.append("Tasks database not found in registry.")
            return 0
        }

        for file in files where file.pathExtension == "md" {
            do {
                let content = try String(contentsOf: file, encoding: .utf8)
                let frontmatter = parseFrontmatter(content)
                guard !frontmatter.isEmpty else { continue }

                let cells: [String: String] = [
                    "title": frontmatter["title"] ?? file.deletingPathExtension().lastPathComponent,
                    "type": frontmatter["type"] ?? "academics",
                    "subject": frontmatter["subject"] ?? "",
                    "date": frontmatter["date"] ?? "",
                    "time": frontmatter["time"] ?? "",
                    "duration": frontmatter["duration"] ?? "",
                    "priority": frontmatter["priority"] ?? "medium",
                    "status": frontmatter["status"] ?? "open",
                    "project": frontmatter["project"] ?? "",
                ]

                let doc = try await databaseRepo.openDocument(id: dbID)
                try await doc.loadIfNeeded()
                await doc.insertRow(TableRowRecord(cells: cells))
                count += 1
            } catch {
                result.errors.append("Failed to migrate task \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if count > 0 {
            do {
                try await databaseRepo.flush(databaseID: dbID)
            } catch {
                result.errors.append("Failed to flush tasks: \(error.localizedDescription)")
            }
        }

        return count
    }

    private func migrateSessions(_ result: inout MigrationResult) async -> Int {
        let sessionsDir = zoraRoot.appendingPathComponent("Sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil) else {
            return 0
        }

        var count = 0
        let sessionsDB: DatabaseRegistryRecord?
        do {
            sessionsDB = try await databaseRepo.databaseRecord(kind: .sessions)
        } catch {
            result.errors.append("Could not find Sessions database: \(error.localizedDescription)")
            return 0
        }

        guard let dbID = sessionsDB?.id else {
            result.errors.append("Sessions database not found in registry.")
            return 0
        }

        for file in files where file.pathExtension == "md" {
            do {
                let content = try String(contentsOf: file, encoding: .utf8)
                let frontmatter = parseFrontmatter(content)
                guard !frontmatter.isEmpty else { continue }

                let cells: [String: String] = [
                    "title": frontmatter["title"] ?? file.deletingPathExtension().lastPathComponent,
                    "type": frontmatter["type"] ?? "session",
                    "subject": frontmatter["subject"] ?? "",
                    "topic": frontmatter["topic"] ?? "",
                    "sessionType": frontmatter["session_type"] ?? frontmatter["sessionType"] ?? "",
                    "date": frontmatter["date"] ?? "",
                    "startTime": frontmatter["start_time"] ?? frontmatter["startTime"] ?? "",
                    "duration": frontmatter["duration"] ?? "",
                    "objective": frontmatter["objective"] ?? "",
                    "status": frontmatter["status"] ?? "planned",
                ]

                let doc = try await databaseRepo.openDocument(id: dbID)
                try await doc.loadIfNeeded()
                await doc.insertRow(TableRowRecord(cells: cells))
                count += 1
            } catch {
                result.errors.append("Failed to migrate session \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if count > 0 {
            do {
                try await databaseRepo.flush(databaseID: dbID)
            } catch {
                result.errors.append("Failed to flush sessions: \(error.localizedDescription)")
            }
        }

        return count
    }

    private func parseFrontmatter(_ content: String) -> [String: String] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else { return [:] }

        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return [:] }

        var result: [String: String] = [:]
        var inFrontmatter = false
        for line in lines {
            let s = String(line).trimmingCharacters(in: .whitespaces)
            if s == "---" {
                if inFrontmatter { break }
                inFrontmatter = true
                continue
            }
            if inFrontmatter {
                let parts = s.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    if value.hasPrefix("\"") && value.hasSuffix("\"") {
                        value = String(value.dropFirst().dropLast())
                    }
                    result[key] = value
                }
            }
        }
        return result
    }
}
