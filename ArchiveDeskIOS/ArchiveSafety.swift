import Foundation

enum ArchiveSafety {
    static let maximumEntries = 100_000
    static let maximumPathBytes = 4_096
    static let maximumComponents = 128
    static let maximumExpandedBytes: UInt64 = 256 * 1_024 * 1_024 * 1_024

    static func validate(entries: [ArchiveEntry], archiveBytes: UInt64) throws -> UInt64 {
        guard entries.count <= maximumEntries else { throw ArchiveFailure.malformed("The archive contains too many entries.") }
        var normalized = Set<String>()
        var files = Set<String>()
        var components: [String: String] = [:]
        var total: UInt64 = 0
        for entry in entries {
            guard !entry.isLink else { throw ArchiveFailure.unsafePath(entry.path) }
            let key = try safeRelativePath(entry.path)
            guard normalized.insert(key).inserted else { throw ArchiveFailure.unsafePath(entry.path) }
            if !entry.isDirectory { files.insert(key) }
            var rawPrefix = ""
            for component in entry.path.split(separator: "/") {
                rawPrefix = rawPrefix.isEmpty ? String(component) : rawPrefix + "/" + component
                let normalizedPrefix = rawPrefix.precomposedStringWithCanonicalMapping.lowercased()
                if let existing = components[normalizedPrefix], existing.utf8.elementsEqual(rawPrefix.utf8) == false {
                    throw ArchiveFailure.unsafePath(entry.path)
                }
                components[normalizedPrefix] = rawPrefix
            }
            guard entry.uncompressedSize <= maximumExpandedBytes - total else { throw ArchiveFailure.capacity }
            total += entry.uncompressedSize
        }
        for name in normalized {
            var prefix = (name as NSString).deletingLastPathComponent
            while !prefix.isEmpty {
                guard !files.contains(prefix) else { throw ArchiveFailure.unsafePath(name) }
                prefix = (prefix as NSString).deletingLastPathComponent
            }
        }
        if archiveBytes > 0, total > 10 * 1_024 * 1_024 * 1_024, total / archiveBytes > 10_000 {
            throw ArchiveFailure.malformed("The expansion ratio is unsafe.")
        }
        return total
    }

    static func safeRelativePath(_ path: String) throws -> String {
        guard !path.isEmpty, path.utf8.count < maximumPathBytes, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"), !path.contains("\0") else {
            throw ArchiveFailure.unsafePath(path)
        }
        let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count <= maximumComponents,
              pieces.dropLast().allSatisfy({ !$0.isEmpty }),
              pieces.allSatisfy({ $0 != "." && $0 != ".." && $0.utf8.count <= 255 }) else {
            throw ArchiveFailure.unsafePath(path)
        }
        return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .precomposedStringWithCanonicalMapping.lowercased()
    }

    /// Preserve spelling on output. Normalized keys are only for collision detection.
    static func outputPath(_ path: String) throws -> String {
        _ = try safeRelativePath(path)
        return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
