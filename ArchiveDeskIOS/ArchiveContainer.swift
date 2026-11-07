import Foundation

/// Immutable snapshot plus a format-specific, in-process reader.
enum ArchiveContainer: Sendable {
    case zip(ZIPArchive)
    case native(MultiFormatArchive)
    case rar(RARArchive)

    var url: URL { switch self { case .zip(let a): a.url; case .native(let a): a.url; case .rar(let a): a.url } }
    var entries: [ArchiveEntry] { switch self { case .zip(let a): a.entries; case .native(let a): a.entries; case .rar(let a): a.entries } }
    var formatName: String { switch self { case .zip: "ZIP"; case .native(let a): a.formatName; case .rar(let a): a.formatName } }
    func requiresPassword(_ entry: ArchiveEntry) -> Bool {
        if case .rar(let rar) = self { return rar.requiresPassword(entry) }
        return entry.isEncrypted
    }

    static func open(url: URL, password: String? = nil, zipEncoding: ArchiveEncoding = .auto) throws -> Self {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let signature = try handle.read(upToCount: 8) ?? Data()
        if signature.starts(with: [0x52, 0x61, 0x72, 0x21, 0x1a, 0x07]) {
            return .rar(try RARArchive.open(url: url, password: password))
        }
        // Keep the stricter existing ZIP central/local-header validation.
        if signature.starts(with: [0x50, 0x4b]) || ["zip", "zipx", "ipa", "apk", "jar", "epub"].contains(url.pathExtension.lowercased()) {
            return .zip(try ZIPArchive.open(url: url, filenameEncoding: zipEncoding))
        }
        return .native(try MultiFormatArchive.open(url: url))
    }
    func previewText(_ entry: ArchiveEntry, password: String? = nil) throws -> String? {
        switch self { case .zip(let a): try a.previewText(entry); case .native(let a): try a.previewText(entry); case .rar(let a): try a.previewText(entry, password: password) }
    }
    func previewTextBytes(_ entry: ArchiveEntry, password: String? = nil) throws -> Data? {
        switch self { case .zip(let a): try a.previewTextBytes(entry); case .native(let a): try a.previewTextBytes(entry); case .rar(let a): try a.previewTextBytes(entry, password: password) }
    }
    func extract(paths: Set<String>? = nil, outputRoot: URL, createOutputRoot: Bool = true, password: String? = nil,
                 progress: @escaping ArchiveProgress = { _, _ in }, direct: DirectExtractionOutput? = nil) throws -> URL {
        switch self {
        case .zip(let a): try a.extract(paths: paths, outputRoot: outputRoot, createOutputRoot: createOutputRoot, progress: progress, direct: direct)
        case .native(let a): try a.extract(paths: paths, outputRoot: outputRoot, createOutputRoot: createOutputRoot, progress: progress, direct: direct)
        case .rar(let a): try a.extract(paths: paths, outputRoot: outputRoot, createOutputRoot: createOutputRoot, password: password, progress: progress, direct: direct)
        }
    }
    func extractForUser(paths: Set<String>? = nil, outputRoot: URL, createOutputRoot: Bool = true, password: String? = nil,
                        progress: @escaping ArchiveProgress = { _, _ in }, mergeExisting: Bool, useStaging: Bool = false,
                        conflict: (String) throws -> ExtractionConflictChoice) throws -> URL {
        if !useStaging {
            if createOutputRoot { try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true) }
            try ExtractionPublication.checkDirectory(outputRoot)
            let destination = mergeExisting ? outputRoot : outputRoot.appendingPathComponent("Extracted-" + UUID().uuidString, isDirectory: true)
            if !mergeExisting { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false) }
            let selected = entries.filter { paths == nil || paths!.contains($0.path) }
            let direct = try DirectExtractionOutput(entries: selected, directory: destination, conflict: conflict)
            return try extract(paths: paths, outputRoot: destination, createOutputRoot: false, password: password, progress: progress, direct: direct)
        }
        let decoded = try extract(paths: paths, outputRoot: outputRoot, createOutputRoot: createOutputRoot, password: password, progress: progress)
        guard mergeExisting else { return decoded }
        do {
            try ExtractionPublication.merge(decoded, into: outputRoot, conflict: conflict)
            try FileManager.default.removeItem(at: decoded)
            return outputRoot
        } catch {
            let original = error
            if FileManager.default.fileExists(atPath: decoded.path) {
                do { try FileManager.default.removeItem(at: decoded) }
                catch { throw ExtractionRollbackFailure(stagingFolder: decoded.lastPathComponent, cause: original.localizedDescription) }
            }
            throw original
        }
    }
}
