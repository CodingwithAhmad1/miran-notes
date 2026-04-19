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
    /// A single directory contains both note files and subfolders (dashboard vs repository layout).
    case folderContainsNotesAndSubfolders
    case disallowedRootFile
    case disallowedItemInNoteFolder
    case symlinkNotAllowed
    case unreadableDirectory
    /// Both `.txt` and `.md` note bodies appear in the same folder.
    case mixedNoteBodyExtensionsInFolder
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
/// Top-level directories (except `.miran` / `_aux`) are topic folders. Each directory may contain either **note files** (and sidecars) **or** **nested subfolders** (dashboard hubs), not both in the same folder—matching dashboard vs repository folder semantics. Nested directories are scanned recursively; leaf folders hold notes only. Canonical multi-segment note paths and indexes follow ADR 0003 (`docs/adr/0003-folders-paths-and-manifest-v2.md`).
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
                if WorkspaceCompatibilityPolicy.noteBodyExtensions.contains(ext) {
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
                        message: "Only .txt or .md notes (and .meta.json sidecars) are allowed at the workspace root.",
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

        var rootNoteBodyExtensions = Set<String>()
        for rn in rootNoteEntries {
            let ext = (rn.fileName as NSString).pathExtension.lowercased()
            if WorkspaceCompatibilityPolicy.noteBodyExtensions.contains(ext) {
                rootNoteBodyExtensions.insert(ext)
            }
        }
        if rootNoteBodyExtensions.count > 1 {
            issues.append(
                CompatibilityIssue(
                    code: .mixedNoteBodyExtensionsInFolder,
                    message: "The vault root cannot mix .txt and .md notes in the same folder; use one body format only.",
                    path: WorkspaceRelativePath(".")
                )
            )
        }

        for folderURL in topicFolders.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            let folderName = folderURL.lastPathComponent
            let folderRel = WorkspaceRelativePath(folderName)
            folderEntries.append(WorkspaceFolderScanEntry(name: folderName, relativePath: folderRel))
            scanVaultFolderContents(
                at: folderURL,
                posixPrefix: folderName,
                issues: &issues,
                folderEntries: &folderEntries,
                noteEntries: &noteEntries
            )
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

    /// Recursively scans a vault topic or nested folder: each directory may contain either note files or subfolders, not both.
    private static func scanVaultFolderContents(
        at dirURL: URL,
        posixPrefix: String,
        issues: inout [CompatibilityIssue],
        folderEntries: inout [WorkspaceFolderScanEntry],
        noteEntries: inout [WorkspaceNoteScanEntry]
    ) {
        let inner: [URL]
        do {
            inner = try FileManager.default.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsSubdirectoryDescendants]
            )
        } catch {
            issues.append(
                CompatibilityIssue(
                    code: .unreadableDirectory,
                    message: "Could not read folder “\(posixPrefix)”: \(error.localizedDescription)",
                    path: WorkspaceRelativePath(posixPrefix)
                )
            )
            return
        }

        var childDirs: [URL] = []
        var bodyExtensionsSeenInFolder = Set<String>()
        var hasDirectNoteFile = false
        let parentDisplayName = (posixPrefix as NSString).lastPathComponent

        for item in inner {
            let values = try? item.resourceValues(forKeys: resourceKeys)
            let isSymlink = values?.isSymbolicLink == true
            let isDirectory = values?.isDirectory == true
            let isRegular = values?.isRegularFile == true
            let itemName = item.lastPathComponent
            let itemRel = WorkspaceRelativePath("\(posixPrefix)/\(itemName)")

            if isSymlink {
                issues.append(
                    CompatibilityIssue(
                        code: .symlinkNotAllowed,
                        message: "Symbolic links are not allowed inside vault folders.",
                        path: itemRel
                    )
                )
                continue
            }

            if isDirectory {
                childDirs.append(item)
                continue
            }

            if isRegular {
                if WorkspaceCompatibilityPolicy.ignoredNoiseFileNames.contains(itemName) {
                    continue
                }
                let ext = item.pathExtension.lowercased()
                if WorkspaceCompatibilityPolicy.noteBodyExtensions.contains(ext) {
                    hasDirectNoteFile = true
                    bodyExtensionsSeenInFolder.insert(ext)
                    let stem = (itemName as NSString).deletingPathExtension
                    let relNoExt = "\(posixPrefix)/\(stem)"
                    noteEntries.append(
                        WorkspaceNoteScanEntry(
                            fileName: itemName,
                            relativePathWithoutExtension: relNoExt,
                            parentFolderName: parentDisplayName
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
                        message: "Only .txt or .md notes (and .meta.json sidecars) are allowed inside vault folders.",
                        path: itemRel
                    )
                )
                continue
            }

            issues.append(
                CompatibilityIssue(
                    code: .disallowedItemInNoteFolder,
                    message: "Unexpected item inside vault folder.",
                    path: itemRel
                )
            )
        }

        if !childDirs.isEmpty, hasDirectNoteFile {
            issues.append(
                CompatibilityIssue(
                    code: .folderContainsNotesAndSubfolders,
                    message: "A folder cannot contain both notes and subfolders (use a Dashboard folder for nesting).",
                    path: WorkspaceRelativePath(posixPrefix)
                )
            )
            return
        }

        if bodyExtensionsSeenInFolder.count > 1 {
            issues.append(
                CompatibilityIssue(
                    code: .mixedNoteBodyExtensionsInFolder,
                    message: "Folder “\(parentDisplayName)” mixes .txt and .md notes. Use one body format per folder.",
                    path: WorkspaceRelativePath(posixPrefix)
                )
            )
        }

        for sub in childDirs.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            let name = sub.lastPathComponent
            let childPrefix = "\(posixPrefix)/\(name)"
            folderEntries.append(WorkspaceFolderScanEntry(name: name, relativePath: WorkspaceRelativePath(childPrefix)))
            scanVaultFolderContents(
                at: sub,
                posixPrefix: childPrefix,
                issues: &issues,
                folderEntries: &folderEntries,
                noteEntries: &noteEntries
            )
        }
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
