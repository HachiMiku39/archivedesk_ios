import Foundation

/// Immutable snapshot plus a format-specific, in-process reader.
enum ArchiveContainer: Sendable {
    case zip(ZIPArchive)
    case native(MultiFormatArchive)

    var url: URL { switch self { case .zip(let a): a.url; case .native(let a): a.url } }
    var entries: [ArchiveEntry] { switch self { case .zip(let a): a.entries; case .native(let a): a.entries } }
    var formatName: String { switch self { case .zip: "ZIP"; case .native(let a): a.formatName } }

    static func open(url: URL) throws -> Self {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let signature = try handle.read(upToCount: 4) ?? Data()
        // Keep the stricter existing ZIP central/local-header validation.
        if signature.starts(with: [0x50, 0x4b]) || ["zip", "zipx", "ipa", "apk", "jar", "epub"].contains(url.pathExtension.lowercased()) {
            return .zip(try ZIPArchive.open(url: url))
        }
        return .native(try MultiFormatArchive.open(url: url))
    }
    func previewText(_ entry: ArchiveEntry) throws -> String? {
        switch self { case .zip(let a): try a.previewText(entry); case .native(let a): try a.previewText(entry) }
    }
    func extract(paths: Set<String>? = nil, outputRoot: URL, createOutputRoot: Bool = true) throws -> URL {
        switch self {
        case .zip(let a): try a.extract(paths: paths, outputRoot: outputRoot, createOutputRoot: createOutputRoot)
        case .native(let a): try a.extract(paths: paths, outputRoot: outputRoot, createOutputRoot: createOutputRoot)
        }
    }
}
