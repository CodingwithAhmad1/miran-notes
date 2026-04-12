import AppKit
import CryptoKit
import Foundation
import MiranNotesCore
import os.log

extension Logger {
    static let editorSync = Logger(subsystem: "app.miran.notes", category: "EditorSync")
}

/// **Canonical boundary** for moving canonical `NoteDocument.text` into `NSTextView` and verifying alignment.
///
/// **Invariant policy:** All `NSTextStorage` / `NSTextView.string` mutations that reflect the canonical model
/// must go through this type (except IME composition — callers must skip when `hasMarkedText()`).
///
/// Forbidden pattern: calling `textStorage.replaceCharacters` or assigning `textView.string` directly from
/// `Coordinator` except through ``applyModelText(to:modelText:isApplyingModelUpdate:)`` and
/// ``applyCanonicalDocument(to:newDoc:isApplyingModelUpdate:)``.
enum EditorSyncController {
    /// Probability `1/driftSampleRate` that we hash-compare model vs `NSTextView` (0 = disabled). DEBUG enables light sampling.
    #if DEBUG
    static let driftSampleRate: UInt32 = 256
    #else
    static let driftSampleRate: UInt32 = 0
    #endif

    // MARK: - Fingerprints

    /// Stable fingerprint for drift checks: note identity + structure count + full UTF-8 body bytes.
    static func fingerprint(document: NoteDocument) -> String {
        fingerprintBytes(noteID: document.metadata.noteID, blockCount: document.metadata.blocks.count, utf8Text: document.text)
    }

    /// Fingerprint from plain string (must match `document.text` when the editor is in sync).
    static func fingerprint(viewText: String, noteID: UUID, blockCount: Int) -> String {
        fingerprintBytes(noteID: noteID, blockCount: blockCount, utf8Text: viewText)
    }

    private static func fingerprintBytes(noteID: UUID, blockCount: Int, utf8Text: String) -> String {
        var payload = Data()
        payload.append(contentsOf: noteID.uuidString.utf8)
        payload.append(0x1E) // RS separator
        payload.append(contentsOf: String(blockCount).utf8)
        payload.append(0x1E)
        payload.append(Data(utf8Text.utf8))
        return SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Model → view

    enum ModelToViewSync: Equatable {
        case alreadyAligned
        case incremental(range: NSRange, replacement: String)
        case fullStringReplace
    }

    /// Decides how to align the text view with `modelText` given the current `viewString`.
    static func modelToViewSync(viewString: String, modelText: String) -> ModelToViewSync {
        if viewString == modelText { return .alreadyAligned }
        if let diff = TextEditDiff.singleUTF16Replacement(from: viewString, to: modelText) {
            return .incremental(range: diff.range, replacement: diff.replacement)
        }
        return .fullStringReplace
    }

    /// Applies canonical `modelText` when the parent `document` updates (e.g. undo, external reload).
    /// Caller must ensure `!textView.hasMarkedText()`.
    /// - Returns: `true` if a full-string replace ran (caller may need to clamp selection).
    @discardableResult
    static func applyModelText(
        to textView: NSTextView,
        modelText: String,
        isApplyingModelUpdate: inout Bool
    ) -> Bool {
        let viewString = textView.string
        switch modelToViewSync(viewString: viewString, modelText: modelText) {
        case .alreadyAligned:
            return false
        case .incremental(let range, let replacement):
            isApplyingModelUpdate = true
            textView.textStorage?.replaceCharacters(in: range, with: replacement)
            isApplyingModelUpdate = false
            return false
        case .fullStringReplace:
            isApplyingModelUpdate = true
            textView.string = modelText
            isApplyingModelUpdate = false
            return true
        }
    }

    /// After `EditCommand`s run, align the buffer to `newDoc.text` (same rules as incremental vs full).
    static func applyCanonicalDocument(
        to textView: NSTextView,
        newDoc: NoteDocument,
        isApplyingModelUpdate: inout Bool
    ) {
        let viewString = textView.string
        let modelText = newDoc.text
        if viewString == modelText { return }
        if let diff = TextEditDiff.singleUTF16Replacement(from: viewString, to: modelText) {
            isApplyingModelUpdate = true
            textView.textStorage?.replaceCharacters(in: diff.range, with: diff.replacement)
            isApplyingModelUpdate = false
        } else {
            isApplyingModelUpdate = true
            textView.string = modelText
            isApplyingModelUpdate = false
        }
    }

    // MARK: - Drift sampling

    /// When `sampleRate > 0`, logs (approximately `1/sampleRate` of the time) if view text diverges from the model fingerprint.
    static func sampleAndLogDriftIfNeeded(
        document: NoteDocument,
        textView: NSTextView,
        sampleRate: UInt32
    ) {
        guard sampleRate > 0 else { return }
        guard UInt32.random(in: 0..<sampleRate) == 0 else { return }
        let fpDoc = fingerprint(document: document)
        let fpView = fingerprint(viewText: textView.string, noteID: document.metadata.noteID, blockCount: document.metadata.blocks.count)
        if fpDoc != fpView {
            Logger.editorSync.warning("Editor drift sample: fingerprint mismatch doc vs textView")
            assertionFailure("EditorSyncController: model/view fingerprint mismatch (sampled)")
        }
    }
}
