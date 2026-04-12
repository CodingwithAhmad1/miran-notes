import Foundation

enum ExternalBookmarkStatus: String, Codable, Sendable {
    case valid
    case stale
    case denied
    case missing
}

struct ExternalBookmarkRecord: Codable, Equatable, Sendable {
    var id: UUID
    var targetDescription: String
    var bookmarkData: Data
    var status: ExternalBookmarkStatus
    var updatedAt: Date
}

actor ExternalBookmarkStore {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(vaultURL: URL) {
        self.url = VaultPaths.externalBookmarksURL(vaultURL: vaultURL)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func list() throws -> [ExternalBookmarkRecord] {
        try loadAll()
    }

    func upsert(id: UUID, targetDescription: String, bookmarkData: Data, status: ExternalBookmarkStatus) throws {
        var all = try loadAll()
        let next = ExternalBookmarkRecord(
            id: id,
            targetDescription: targetDescription,
            bookmarkData: bookmarkData,
            status: status,
            updatedAt: Date()
        )
        if let index = all.firstIndex(where: { $0.id == id }) {
            all[index] = next
        } else {
            all.append(next)
        }
        try saveAll(all)
    }

    func markStatus(id: UUID, status: ExternalBookmarkStatus) throws {
        var all = try loadAll()
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].status = status
        all[index].updatedAt = Date()
        try saveAll(all)
    }

    private func loadAll() throws -> [ExternalBookmarkRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([ExternalBookmarkRecord].self, from: data)) ?? []
    }

    private func saveAll(_ all: [ExternalBookmarkRecord]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(all)
        try data.write(to: url, options: .atomic)
    }
}
