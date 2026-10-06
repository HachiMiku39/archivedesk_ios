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
        return false
    }

    static func open(url: URL, password: String? = nil) throws -> Self {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let signature = try handle.read(upToCount: 8) ?? Data()
        if signature.starts(with: [0x52, 0x61, 0x72, 0x21, 0x1a, 0x07]) {
            return .rar(try RARArchive.open(url: url, password: password))
        }
        // Keep the stricter existing ZIP central/local-header validation.
        if signature.starts(with: [0x50, 0x4b]) || ["zip", "zipx", "ipa", "apk", "jar", "epub"].contains(url.pathExtension.lowercased()) {
            return .zip(try ZIPArchive.open(url: url))
        }
        return .native(try MultiFormatArchive.open(url: url))
    }
    func previewText(_ entry: ArchiveEntry, password: String? = nil) throws -> String? {
        switch self { case .zip(let a): try a.previewText(entry); case .native(let a): try a.previewText(entry); case .rar(let a): try a.previewText(entry, password: password) }
    }
    func extract(paths: Set<String>? = nil, outputRoot: URL, createOutputRoot: Bool = true, password: String? = nil,
                 progress: @escaping ArchiveProgress = { _, _ in }) throws -> URL {
        switch self {
        case .zip(let a): try a.extract(paths: paths, outputRoot: outputRoot, createOutputRoot: createOutputRoot, progress: progress)
        case .native(let a): try a.extract(paths: paths, outputRoot: outputRoot, createOutputRoot: createOutputRoot, progress: progress)
        case .rar(let a): try a.extract(paths: paths, outputRoot: outputRoot, createOutputRoot: createOutputRoot, password: password, progress: progress)
        }
    }
}
