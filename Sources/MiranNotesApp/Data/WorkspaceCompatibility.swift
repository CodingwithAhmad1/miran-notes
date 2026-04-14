import CryptoKit
import Foundation

// MARK: - Paths

struct WorkspaceRelativePath: Hashable, Sendable, Codable {
    var posixPath: String

    init(_ posixPath: String) {
        self.posixPath = posixPath
    }
}

// MARK: - Scan result model (structural only; bodies loaded later by the app)

struct WorkspaceFolderScanEntry: Hashable, Sendable {
    var name: String
    var relativePath: WorkspaceRelativePath
}

struct WorkspaceNoteScanEntry: Hashable, Sendable {
    var fileName: String
    /// Relative path without `.txt` extension, mirroring ``VaultPath`` / manifest style, e.g. `Business/strategies` or `meeting` at vault root.
    var relativePathWithoutExtension: String
    /// `nil` when the note file sits directly under the workspace root.
    var parentFolderName: String?
}

struct WorkspaceStructureScan: Hashable, Sendable {
    var folders: [WorkspaceFolderScanEntry]
    var notes: [WorkspaceNoteScanEntry]
}

// MARK: - Compatibility

enum WorkspaceScanOutcome: Equatable, Sendable {
    /// Only app-internal / ignored items at root (no topic folders).
    case empty
    case compatible(WorkspaceStructureScan)
    case incompatible(CompatibilityReport)
}

struct CompatibilityReport: Equatable, Sendable {
    var summary: String
    var issues: [CompatibilityIssue]
}

struct CompatibilityIssue: Equatable, Sendable, Identifiable {
    var id: UUID
    var code: IssueCode
    var message: String
    var path: WorkspaceRelativePath?

    init(id: UUID = UUID(), code: IssueCode, message: String, path: WorkspaceRelativePath?) {
        self.id = id
        self.code = code
        self.message = message
        self.path = path
    }
}

enum IssueCode: String, Sendable, Codable {
    case nestedFolder
    case disallowedRootFile
    case disallowedItemInNoteFolder
    case symlinkNotAllowed
    case unreadableDirectory
}

// MARK: - Metadata (optional; computed when loading note bodies)

struct WorkspaceNoteFileMetadata: Hashable, Sendable {
    var noteKey: String
    var inferredTitle: String
    var contentEncoding: String
    var byteCount: Int
    var contentHash: Data
    var fsCreatedAt: Date?
    var fsModifiedAt: Date?
}

/// Structural gate for the vault root before the main shell loads.
///
/// Implements the **flat topic-folder** layout: top-level directories (except `.miran` / `_aux`) are topic folders; each topic folder’s **immediate** children must be note files or ignored noise—**not** nested directories or symbolic links. This aligns with ``NoteRepository/createFolder``, which only adds folders under the catalog root. Canonical multi-segment note paths and indexes follow ADR 0003 (`docs/adr/0003-folders-paths-and-manifest-v2.md`).
///
/// **Symlinks:** Reported as ``IssueCode/symlinkNotAllowed`` at scanned levels. The scanner does not walk every manifest path to re-validate symlinks on each segment.
enum WorkspaceCompatibilityScanner {
    private static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
    ]

    static func scan(vaultRoot: URL) -> WorkspaceScanOutcome {
        let root = vaultRoot.standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            return .incompatible(
                CompatibilityReport(
                    summary: "Workspace not compatible",
                    issues: [
                        CompatibilityIssue(
                            code: .unreadableDirectory,
                            message: "The chosen path is not a directory.",
                            path: nil
                        ),
                    ]
                )
            )
        }

        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsSubdirectoryDescendants]
            )
        } catch {
            return .incompatible(
                CompatibilityReport(
                    summary: "Workspace not compatible",
                    issues: [
                        CompatibilityIssue(
                            code: .unreadableDirectory,
                            message: "Could not read workspace folder: \(error.localizedDescription)",
                            path: nil
                        ),
                    ]
                )
            )
        }

        var issues: [CompatibilityIssue] = []
        var topicFolders: [URL] = []
        var rootNoteEntries: [WorkspaceNoteScanEntry] = []

        for url in children {
            let values = try? url.resourceValues(forKeys: resourceKeys)
            let isSymlink = values?.isSymbolicLink == true
            let isDirectory = values?.isDirectory == true
            let isRegular = values?.isRegularFile == true

            let name = url.lastPathComponent

            if isSymlink {
                issues.append(
                    CompatibilityIssue(
                        code: .symlinkNotAllowed,
                        message: "Symbolic links are not allowed in the workspace.",
                        path: WorkspaceRelativePath(name)
                    )
                )
                continue
            }

            if isDirectory {
                if WorkspaceCompatibilityPolicy.appRootDirectoryNames.contains(name) {
                    continue
                }
                topicFolders.append(url)
                continue
            }

            if isRegular {
                if WorkspaceCompatibilityPolicy.ignoredNoiseFileNames.contains(name) {
                    continue
                }
                if WorkspaceCompatibilityPolicy.allowedOptionalRootFileNames.contains(name) {
                    continue
                }
                let ext = url.pathExtension.lowercased()
                if ext == WorkspaceCompatibilityPolicy.noteFileExtension {
                    let stem = (name as NSString).deletingPathExtension
                    rootNoteEntries.append(
                        WorkspaceNoteScanEntry(
                            fileName: name,
                            relativePathWithoutExtension: stem,
                            parentFolderName: nil
                        )
                    )
                    continue
                }
                if name.lowercased().hasSuffix(WorkspaceCompatibilityPolicy.metadataSidecarSuffix) {
                    continue
                }
                issues.append(
                    CompatibilityIssue(
                        code: .disallowedRootFile,
                        message: "Only .txt notes (and .meta.json sidecars) are allowed at the workspace root.",
                        path: WorkspaceRelativePath(name)
                    )
                )
                continue
            }

            issues.append(
                CompatibilityIssue(
                    code: .disallowedRootFile,
                    message: "Unexpected item at workspace root.",
                    path: WorkspaceRelativePath(name)
                )
            )
        }

        if !issues.isEmpty {
            return report(from: issues)
        }

        var folderEntries: [WorkspaceFolderScanEntry] = []
        var noteEntries: [WorkspaceNoteScanEntry] = rootNoteEntries

        for folderURL in topicFolders.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            let folderName = folderURL.lastPathComponent
            let folderRel = WorkspaceRelativePath(folderName)

            let inner: [URL]
            do {
                inner = try FileManager.default.contentsOfDirectory(
                    at: folderURL,
                    includingPropertiesForKeys: Array(resourceKeys),
                    options: [.skipsSubdirectoryDescendants]
                )
            } catch {
                issues.append(
                    CompatibilityIssue(
                        code: .unreadableDirectory,
                        message: "Could not read folder “\(folderName)”: \(error.localizedDescription)",
                        path: folderRel
                    )
                )
                continue
            }

            folderEntries.append(WorkspaceFolderScanEntry(name: folderName, relativePath: folderRel))

            for item in inner {
                let values = try? item.resourceValues(forKeys: resourceKeys)
                let isSymlink = values?.isSymbolicLink == true
                let isDirectory = values?.isDirectory == true
                let isRegular = values?.isRegularFile == true
                let itemName = item.lastPathComponent
                let itemRel = WorkspaceRelativePath("\(folderName)/\(itemName)")

                if isSymlink {
                    issues.append(
                        CompatibilityIssue(
                            code: .symlinkNotAllowed,
                            message: "Symbolic links are not allowed inside topic folders.",
                            path: itemRel
                        )
                    )
                    continue
                }

                if isDirectory {
                    issues.append(
                        CompatibilityIssue(
                            code: .nestedFolder,
                            message: "Nested folders are not allowed (folders may only contain note files).",
                            path: itemRel
                        )
                    )
                    continue
                }

                if isRegular {
                    if WorkspaceCompatibilityPolicy.ignoredNoiseFileNames.contains(itemName) {
                        continue
                    }
                    let ext = item.pathExtension.lowercased()
                    if ext == WorkspaceCompatibilityPolicy.noteFileExtension {
                        let stem = (itemName as NSString).deletingPathExtension
                        let relNoExt = "\(folderName)/\(stem)"
                        noteEntries.append(
                            WorkspaceNoteScanEntry(
                                fileName: itemName,
                                relativePathWithoutExtension: relNoExt,
                                parentFolderName: folderName
                            )
                        )
                        continue
                    }
                    if itemName.lowercased().hasSuffix(WorkspaceCompatibilityPolicy.metadataSidecarSuffix) {
                        continue
                    }
                    issues.append(
                        CompatibilityIssue(
                            code: .disallowedItemInNoteFolder,
                            message: "Only .txt notes (and .meta.json sidecars) are allowed inside topic folders.",
                            path: itemRel
                        )
                    )
                    continue
                }

                issues.append(
                    CompatibilityIssue(
                        code: .disallowedItemInNoteFolder,
                        message: "Unexpected item inside topic folder.",
                        path: itemRel
                    )
                )
            }
        }

        if !issues.isEmpty {
            return report(from: issues)
        }

        if folderEntries.isEmpty, noteEntries.isEmpty {
            return .empty
        }

        let scan = WorkspaceStructureScan(folders: folderEntries, notes: noteEntries)
        return .compatible(scan)
    }

    /// Builds metadata for a `.txt` file (never throws for read errors — uses empty data on failure).
    static func metadataForNoteTextFile(at url: URL, relativePathWithoutExtension: String) -> WorkspaceNoteFileMetadata {
        let data = (try? Data(contentsOf: url)) ?? Data()
        let digest = SHA256.hash(data: data)
        let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let title = (url.deletingPathExtension().lastPathComponent as String)
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        _ = text
        return WorkspaceNoteFileMetadata(
            noteKey: relativePathWithoutExtension,
            inferredTitle: title,
            contentEncoding: "utf-8",
            byteCount: data.count,
            contentHash: Data(digest),
            fsCreatedAt: resourceValues?.creationDate,
            fsModifiedAt: resourceValues?.contentModificationDate
        )
    }

    private static func report(from issues: [CompatibilityIssue]) -> WorkspaceScanOutcome {
        .incompatible(
            CompatibilityReport(
                summary: "Workspace not compatible",
                issues: issues
            )
        )
    }
}
