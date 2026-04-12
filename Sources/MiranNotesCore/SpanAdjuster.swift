import Foundation

enum SpanAdjuster {
    static func adjust(
        spans: [Span],
        replacedRange: TextRange,
        replacementUTF16Length: Int,
        constrainedTo blocks: [Block]
    ) -> [Span] {
        let delta = replacementUTF16Length - replacedRange.length

        let shifted: [Span] = spans.compactMap { span in
            if span.range.end <= replacedRange.start {
                return span
            }

            if span.range.start >= replacedRange.end {
                let shiftedStart = max(0, span.range.start + delta)
                return Span(
                    range: TextRange(start: shiftedStart, length: span.range.length),
                    style: span.style
                )
            }

            let newStart = min(span.range.start, replacedRange.start)
            let newEnd = max(newStart, span.range.end + delta)
            let updated = TextRange(start: newStart, length: max(0, newEnd - newStart))
            return updated.isEmpty ? nil : Span(range: updated, style: span.style)
        }

        return splitAcrossBlockBoundaries(spans: shifted, blocks: blocks)
    }

    /// Clips spans so that none cross a block boundary. Called after `splitBlock` to keep span metadata consistent.
    static func constrainToBlocks(spans: [Span], blocks: [Block]) -> [Span] {
        splitAcrossBlockBoundaries(spans: spans, blocks: blocks)
    }

    private static func splitAcrossBlockBoundaries(spans: [Span], blocks: [Block]) -> [Span] {
        guard !blocks.isEmpty else { return [] }
        var adjusted: [Span] = []

        for span in spans {
            let intersections = blocks.compactMap { block -> Span? in
                let start = max(span.range.start, block.range.start)
                let end = min(span.range.end, block.range.end)
                guard end > start else { return nil }
                return Span(
                    range: TextRange(start: start, length: end - start),
                    style: span.style
                )
            }
            adjusted.append(contentsOf: intersections)
        }

        return adjusted
    }
}
