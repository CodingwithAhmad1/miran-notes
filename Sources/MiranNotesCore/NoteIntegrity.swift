import Foundation
import os.log

/// Single entry point for structural validation of a note's text vs metadata (Phase 4).
public enum NoteIntegrity {
    public struct Report: Equatable, Sendable {
        public var isValid: Bool
        public var issues: [Issue]

        public init(isValid: Bool, issues: [Issue]) {
            self.isValid = isValid
            self.issues = issues
        }
    }

    public enum Issue: Equatable, Sendable {
        case noBlocks
        case blocksNotSorted
        case gapOrOverlap(atBlockIndex: Int, expectedStart: Int, actualStart: Int)
        case blocksDoNotCoverText(expectedEnd: Int, actualEnd: Int)
        case blockOutOfBounds(blockIndex: Int, range: TextRange, textLength: Int)
        case spanOutOfBounds(spanIndex: Int, range: TextRange, textLength: Int)
        case linkOutOfBounds(linkIndex: Int, range: TextRange, textLength: Int)
    }

    /// Validates partition and span bounds. Does not mutate the document.
    public static func check(document: NoteDocument) -> Report {
        let text = document.text
        let metadata = document.metadata
        let total = RangeNormalizer.utf16Length(of: text)
        var issues: [Issue] = []

        if metadata.blocks.isEmpty {
            issues.append(.noBlocks)
            return Report(isValid: false, issues: issues)
        }

        let sortedBlocks = metadata.blocks.sorted {
            if $0.range.start != $1.range.start {
                return $0.range.start < $1.range.start
            }
            return $0.id < $1.id
        }
        if zip(metadata.blocks, sortedBlocks).contains(where: { $0.id != $1.id }) {
            issues.append(.blocksNotSorted)
        }

        var cursor = 0
        for (index, block) in sortedBlocks.enumerated() {
            if block.range.start != cursor {
                issues.append(.gapOrOverlap(atBlockIndex: index, expectedStart: cursor, actualStart: block.range.start))
            }
            if block.range.end > total {
                issues.append(.blockOutOfBounds(blockIndex: index, range: block.range, textLength: total))
            }
            cursor = block.range.end
        }

        if cursor != total {
            issues.append(.blocksDoNotCoverText(expectedEnd: total, actualEnd: cursor))
        }

        for (index, span) in metadata.spans.enumerated() {
            if span.range.start < 0 || span.range.end > total {
                issues.append(.spanOutOfBounds(spanIndex: index, range: span.range, textLength: total))
            }
        }

        for (index, link) in metadata.links.enumerated() {
            if link.range.start < 0 || link.range.end > total {
                issues.append(.linkOutOfBounds(linkIndex: index, range: link.range, textLength: total))
            }
        }

        let valid = issues.isEmpty && RangeNormalizer.isValid(metadata: metadata, for: text)
        return Report(isValid: valid, issues: issues)
    }

    /// Logs a compact report at `info` when invalid (release-safe, low volume).
    public static func logIfInvalid(document: NoteDocument, logger: Logger = .noteIntegrity) {
        let report = check(document: document)
        guard !report.isValid else { return }
        logger.info("Note integrity: invalid — \(report.issues.map { String(describing: $0) }.joined(separator: "; "), privacy: .public)")
    }
}

extension Logger {
    public static let noteIntegrity = Logger(subsystem: "app.miran.notes", category: "NoteIntegrity")
}
