import Foundation
import MiranNotesCore

struct PlanningConfig: Codable, Equatable {
    var subjects: [String]
    var taskTypes: [String]
    var colorSchema: [String: String]
    var quickAddDefaults: QuickAddDefaults
    var dailyTemplate: String
    var notificationSettings: PlanningNotificationSettings

    struct QuickAddDefaults: Codable, Equatable {
        var defaultPriority: String
        var defaultType: String

        init(defaultPriority: String = "medium", defaultType: String = "academics") {
            self.defaultPriority = defaultPriority
            self.defaultType = defaultType
        }
    }

    struct PlanningNotificationSettings: Codable, Equatable {
        var enabled: Bool
        var leadTimeMinutes: Int

        init(enabled: Bool = false, leadTimeMinutes: Int = 5) {
            self.enabled = enabled
            self.leadTimeMinutes = leadTimeMinutes
        }
    }

    static let `default` = PlanningConfig(
        subjects: ["MathFM", "Economics", "English"],
        taskTypes: ["academics", "personal", "admin"],
        colorSchema: [
            "session": "#6366F1",
            "block": "#64748B",
            "habit": "#22C55E",
            "event": "#A855F7",
            "task": "#F59E0B",
            "MathFM": "#6366F1",
            "Economics": "#14B8A6",
            "English": "#F43F5E",
        ],
        quickAddDefaults: QuickAddDefaults(),
        dailyTemplate: """
            # {{date}}

            ## Sessions
            {{sessions}}

            ## Tasks
            {{tasks}}

            ## Notes

            """,
        notificationSettings: PlanningNotificationSettings()
    )
}

/// Loads and saves the planning configuration from `.miran/planning-config.json`.
actor PlanningConfigManager {
    private let configURL: URL
    private(set) var config: PlanningConfig

    init(vaultURL: URL) {
        self.configURL = VaultPaths.miranDirectory(vaultURL: vaultURL)
            .appendingPathComponent("planning-config.json", isDirectory: false)
        self.config = .default
    }

    func load() {
        guard let data = try? Data(contentsOf: configURL),
              let decoded = try? JSONDecoder().decode(PlanningConfig.self, from: data) else {
            return
        }
        config = decoded
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
    }

    func update(_ newConfig: PlanningConfig) throws {
        config = newConfig
        try save()
    }

    func updateSubjects(_ subjects: [String]) throws {
        config.subjects = subjects
        try save()
    }
}
