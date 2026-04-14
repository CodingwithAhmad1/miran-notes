import Foundation
import MiranNotesCore

// MARK: - Repair advisory (banner)

enum RepairAdvisoryKind: String, Equatable, Sendable {
    /// Structural alignment on load (may combine with wiki details text).
    case loadStructuralRepair
    case wikiLinksMissingMetadata
    case loadStructuralWithWikiLinks
    case fullBufferFallback
    case sizeLimitExceeded
    /// Interrupted multi-file commit was finished or rolled back at startup.
    case vaultRecoveryCompleted
    /// Post-save or post-rebuild consistency check found index / manifest drift.
    case vaultDataConsistency
    /// A single `apply` batch exceeded ``CommandPipelineContract/maxCommandsPerBatch``; the tail was dropped.
    case commandBatchTruncated
}

struct RepairAdvisory: Equatable, Sendable {
    var kind: RepairAdvisoryKind
    var title: String
    var explanation: String
    /// Plain-text summary for the Details sheet (no internal type names).
    var detailsPlainText: String?

    static func vaultRecoveryNotice(_ summary: VaultRecoverySummary) -> RepairAdvisory {
        var lines: [String] = []
        if summary.resumedAndCompletedCount > 0 {
            lines.append(
                "A previous save was interrupted before it finished. We completed that update safely from temporary files."
            )
        }
        if summary.discardedStagingCount > 0 {
            lines.append(
                "We removed leftover temporary files from an incomplete save. Your last successful save was not changed."
            )
        }
        let explanation = lines.isEmpty
            ? "The library was checked after the last session ended unexpectedly."
            : lines.joined(separator: " ")
        return RepairAdvisory(
            kind: .vaultRecoveryCompleted,
            title: "We checked your notes library",
            explanation: explanation,
            detailsPlainText: nil
        )
    }

    static func vaultIntegrityNotice(_ result: VaultIntegrityResult) -> RepairAdvisory {
        RepairAdvisory(
            kind: .vaultDataConsistency,
            title: "We noticed a data check warning",
            explanation:
                "After saving, something in the saved index or file list did not match expectations. You can keep editing; use Details if you want technical notes for support.",
            detailsPlainText: result.issues.joined(separator: "\n")
        )
    }

    static let fullBufferDetails =
        "The editor replaced the whole note in one step (for example after a complex paste or undo). Section headings were matched back to the text where possible."

    static let sizeLimitDetails =
        "This note has a maximum size. Extra text was not added."

    /// User-visible notice when an edit batch is truncated to the pipeline limit (Release-safe; complements `Logger.editEngine`).
    static func commandBatchTruncated(originalCount: Int, appliedCap: Int) -> RepairAdvisory {
        let dropped = max(0, originalCount - appliedCap)
        return RepairAdvisory(
            kind: .commandBatchTruncated,
            title: "Part of this edit couldn’t be applied",
            explanation:
                "One step tried to make \(originalCount) separate changes. Only the first \(appliedCap) could be applied safely; \(dropped) were skipped. What you see reflects the applied part.",
            detailsPlainText: nil
        )
    }
}

// MARK: - External edit conflict (alert copy)

enum ExternalEditConflictCopy {
    static let alertTitle = "This note changed elsewhere"
    static let alertMessage = """
        The saved copy of this note was modified while you have changes here that are not saved yet.

        Use the saved file to replace what you see with the version on disk. Keep my edits to stay on your current text; saving later may replace the other copy.
        """
    static let buttonKeepEdits = "Keep my edits"
    static let buttonUseSavedFile = "Use the saved file"
    static let buttonShowInFinder = "Show in Finder"
    static let buttonDetails = "Details…"
    static let buttonCompare = "Compare…"

    static func detailsLines(diskDate: Date, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let when = formatter.string(from: diskDate)
        return """
            The note file was last saved on disk at \(when).

            Miran compared that saved copy to your unsaved text in the editor.
            """
    }
}

// MARK: - Diagnostics from load-time warnings

enum RepairDiagnosticsBuilder {
    /// Repository fallback line when metadata cannot be repaired incrementally.
    static let corruptMetadataFallbackLine =
        "Metadata was too corrupt to repair incrementally; rebuilt as single paragraph block."

    static func details(
        repairWarnings: [String],
        hadWikiLinkAdvisory: Bool
    ) -> String? {
        var lines: [String] = []

        let structural = structuralSummary(from: repairWarnings)
        if !structural.isEmpty {
            lines.append(structural)
        }

        if hadWikiLinkAdvisory {
            lines.append(
                "The text uses wiki-style links, but no link information was found in the saved data. Use the link tools in the editor to make links work again."
            )
        }

        if lines.isEmpty { return nil }
        return lines.joined(separator: "\n\n")
    }

    static func structuralSummary(from repairWarnings: [String]) -> String {
        var gapMerges = 0
        var overlapAdjustments = 0
        var trailingAdjustments = 0
        var singleBlockStretch = 0
        var insertedBlock = 0
        var corruptRebuild = 0

        for w in repairWarnings {
            if w == corruptMetadataFallbackLine {
                corruptRebuild += 1
                continue
            }
            switch w {
            case "No blocks found. Inserted one paragraph block.":
                insertedBlock += 1
            case "Found a block gap. Expanded previous block coverage.":
                gapMerges += 1
            case "Adjusted overlapping block ranges.":
                overlapAdjustments += 1
            case "Adjusted trailing block to cover text end.":
                trailingAdjustments += 1
            case "Adjusted single block to cover entire text.":
                singleBlockStretch += 1
            default:
                break
            }
        }

        var phrases: [String] = []
        if corruptRebuild > 0 {
            phrases.append(
                "The saved layout information did not match the text, so the note was opened as one continuous section."
            )
        }
        if insertedBlock > 0 {
            phrases.append("One section was created so the note could be shown.")
        }
        if gapMerges > 0 {
            phrases.append(
                gapMerges == 1
                    ? "Section boundaries were merged in one place so every line belongs to a section."
                    : "Section boundaries were merged in \(gapMerges) places so every line belongs to a section."
            )
        }
        if overlapAdjustments > 0 {
            phrases.append(
                overlapAdjustments == 1
                    ? "Overlapping sections were adjusted once."
                    : "Overlapping sections were adjusted \(overlapAdjustments) times."
            )
        }
        if trailingAdjustments > 0 {
            phrases.append(
                trailingAdjustments == 1
                    ? "The last section was extended to include the end of the text."
                    : "The last section was extended \(trailingAdjustments) times to include the end of the text."
            )
        }
        if singleBlockStretch > 0 {
            phrases.append(
                "A single section was stretched to cover the full note."
            )
        }

        return phrases.joined(separator: " ")
    }

    static func buildLoadAdvisory(result: NoteLoadResult) -> RepairAdvisory? {
        let wasRepaired = result.wasRepaired
        let text = result.document.text
        let hasWikiSyntax = text.contains("[[")
        let hasMissingLinkMetadata = hasWikiSyntax && result.document.metadata.links.isEmpty

        guard wasRepaired || hasMissingLinkMetadata else { return nil }

        let details = Self.details(
            repairWarnings: result.repairWarnings,
            hadWikiLinkAdvisory: hasMissingLinkMetadata
        )

        if wasRepaired && hasMissingLinkMetadata {
            return RepairAdvisory(
                kind: .loadStructuralWithWikiLinks,
                title: "We adjusted this note to open safely",
                explanation:
                    "What you see did not match the saved layout and link information, so we aligned the saved layout to this text. You can keep editing as usual.",
                detailsPlainText: details
            )
        }

        if wasRepaired {
            return RepairAdvisory(
                kind: .loadStructuralRepair,
                title: "We fixed an inconsistency in this note",
                explanation:
                    "The text and saved layout did not agree; we updated the layout to match what you see.",
                detailsPlainText: details
            )
        }

        return RepairAdvisory(
            kind: .wikiLinksMissingMetadata,
            title: "Some links need to be set up again",
            explanation:
                "This text includes link markers, but the saved link list is empty. Add links from the editor to make them work.",
            detailsPlainText: details
        )
    }
}
