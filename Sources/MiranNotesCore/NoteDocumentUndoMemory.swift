import Foundation

extension NoteDocument {
    /// Rough retained size for undo budgeting and tests (not exact RSS).
    /// Uses UTF-16 code unit count × 2 as a stand-in for `String` backing plus a small fixed metadata allowance.
    public var estimatedUndoMemoryBytes: Int {
        let textEstimate = text.utf16.count * 2
        let blockEstimate = metadata.blocks.count * 128
        let spanEstimate = metadata.spans.count * 64
        let linkEstimate = metadata.links.count * 96
        let propsEstimate = metadata.properties.count * 48
        return textEstimate + blockEstimate + spanEstimate + linkEstimate + propsEstimate + 512
    }

    /// Sum of `estimatedUndoMemoryBytes` for each checkpoint (full timeline retained in memory).
    public static func estimatedUndoBytes(forCheckpoints checkpoints: [NoteDocument]) -> Int {
        checkpoints.reduce(0) { $0 + $1.estimatedUndoMemoryBytes }
    }
}
