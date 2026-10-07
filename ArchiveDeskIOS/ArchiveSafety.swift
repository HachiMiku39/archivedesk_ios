import Foundation
import Darwin

enum ArchiveSafety {
    static let maximumEntries = 100_000
    static let maximumPathBytes = 4_096
    static let maximumComponents = 128
    static let maximumExpandedBytes: UInt64 = 256 * 1_024 * 1_024 * 1_024

    static func validate<S: Sequence>(entries: S, archiveBytes: UInt64) throws -> UInt64 where S.Element == ArchiveEntry {
        var normalized = Set<String>()
        var files = Set<String>()
        var components: [String: String] = [:]
        var total: UInt64 = 0
        var count = 0
        for entry in entries {
            try Task.checkCancellation()
            count += 1
            guard count <= maximumEntries else { throw ArchiveFailure.malformed("The archive contains too many entries.") }
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
            guard entry.uncompressedSize <= maximumExpandedBytes - total else { throw ArchiveFailure.resourceLimit("256 GiB total expanded/input bytes") }
            total += entry.uncompressedSize
        }
        for name in normalized {
            try Task.checkCancellation()
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

/// Capacity is an advisory preflight, never a reservation. Refresh URL values
/// and include purgeable space for this user-requested write. Unsupported or
/// missing metadata is not a claim that the volume has zero free bytes.
enum StorageBudget {
    static func available(important: Int64?, ordinary: Int64?, fileSystem: UInt64?) -> UInt64? {
        if let important, important > 0 { return UInt64(important) }
        let candidates = [ordinary.flatMap { $0 > 0 ? UInt64($0) : nil }, fileSystem].compactMap { $0 }
        if let positive = candidates.max(), positive > 0 { return positive }
        if ordinary == 0 || fileSystem == 0 { return 0 }
        return nil
    }
    static func require(_ bytes: UInt64, at url: URL) throws {
        var fresh = url; fresh.removeAllCachedResourceValues()
        let values = try? fresh.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        var fs = statfs()
        let valid = url.path.withCString { statfs($0, &fs) == 0 }
        let blocks = UInt64(fs.f_bavail)
        let blockBytes = UInt64(fs.f_bsize)
        let (free, overflow) = blocks.multipliedReportingOverflow(by: blockBytes)
        let fileSystem: UInt64? = valid && !overflow ? free : nil
        if let available = available(important: values?.volumeAvailableCapacityForImportantUsage,
                                     ordinary: values?.volumeAvailableCapacity.map(Int64.init), fileSystem: fileSystem), available < bytes {
            throw ArchiveFailure.storageSpace(bytes, available)
        }
    }
    static func createFile(at url: URL) throws {
        let fd = url.path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600) }
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard Darwin.close(fd) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
