import Foundation
import Darwin
import CArchive

enum PackingFormat: String, CaseIterable, Identifiable, Sendable {
    case zip, tar
    var id: Self { self }
}

struct PackingItem: Sendable {
    let url: URL
    let path: String
    let size: UInt64
    let isDirectory: Bool
    var entry: ArchiveEntry {
        ArchiveEntry(id: 0, path: path, compressedSize: 0, uncompressedSize: size,
                     crc32: 0, compressionMethod: 0, localHeaderOffset: 0)
    }
}

struct PackingSource: Identifiable, Sendable {
    let id: UUID
    let name: String
    let snapshotDirectory: URL
    let items: [PackingItem]
    var bytes: UInt64 { items.reduce(0) { $0 + $1.size } }
}

enum PackingInput {
    /// One immutable private tree per picked root. The provider grant is never
    /// retained after copying; adding sources from another provider is independent.
    static func snapshot(_ url: URL, name: String, coordinated: Bool = true) throws -> PackingSource {
        _ = try ArchiveSafety.safeRelativePath(name)
        guard !name.contains("/") else { throw ArchiveFailure.unsafePath(name) }
        let id = UUID()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveDesk-Pack-\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: directory) } }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var result: Result<[PackingItem], Error>?
        var coordinationError: NSError?
        let copy: (URL) -> Void = { readable in result = Result { try copyTree(readable, name: name, into: directory) } }
        if coordinated {
            NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError, byAccessor: copy)
        } else { copy(url) } // Host tests only; the app always coordinates picked URLs.
        if let coordinationError { throw coordinationError }
        guard let result else { throw DestinationFailure.invalidDirectory }
        let items = try result.get()
        try Task.checkCancellation()
        succeeded = true
        return PackingSource(id: id, name: name, snapshotDirectory: directory, items: items)
    }

    static func uniqueName(_ proposed: String, used: Set<String>) throws -> String {
        _ = try ArchiveSafety.safeRelativePath(proposed)
        guard !proposed.contains("/") else { throw ArchiveFailure.unsafePath(proposed) }
        let key: (String) -> String = { $0.precomposedStringWithCanonicalMapping.lowercased() }
        let keys = Set(used.map(key))
        if !keys.contains(key(proposed)) { return proposed }
        let ext = (proposed as NSString).pathExtension
        let stem = ext.isEmpty ? proposed : (proposed as NSString).deletingPathExtension
        for number in 2...100_001 {
            let candidate = stem + " (\(number))" + (ext.isEmpty ? "" : "." + ext)
            _ = try ArchiveSafety.safeRelativePath(candidate)
            if !keys.contains(key(candidate)) { return candidate }
        }
        throw ArchiveFailure.capacity
    }

    private static func copyTree(_ root: URL, name: String, into directory: URL) throws -> [PackingItem] {
        let fm = FileManager.default
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        var pending: [(URL, String)] = [(root, name)]
        var items: [PackingItem] = []
        var total: UInt64 = 0
        var pathBytes = 0
        while let (inputURL, path) = pending.popLast() {
            try Task.checkCancellation()
            _ = try ArchiveSafety.safeRelativePath(path)
            guard items.count < ArchiveSafety.maximumEntries else { throw ArchiveFailure.capacity }
            pathBytes += path.utf8.count
            guard pathBytes <= 32 * 1024 * 1024 else { throw ArchiveFailure.capacity }
            let values = try inputURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true,
                  inputURL.resolvingSymlinksInPath().standardizedFileURL.pathComponents.starts(with: canonicalRoot) else {
                throw ArchiveFailure.unsafePath(path)
            }
            let output = directory.appendingPathComponent(path)
            if values.isDirectory == true {
                try fm.createDirectory(at: output, withIntermediateDirectories: false)
                items.append(PackingItem(url: output, path: path + "/", size: 0, isDirectory: true))
                let children = try fm.contentsOfDirectory(at: inputURL, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
                guard children.count <= ArchiveSafety.maximumEntries - items.count - pending.count else { throw ArchiveFailure.capacity }
                for child in children.reversed() { pending.append((child, path + "/" + child.lastPathComponent)) }
            } else {
                guard values.isRegularFile == true else { throw ArchiveFailure.unsafePath(path) }
                let fd = Darwin.open(inputURL.path, O_RDONLY | O_NOFOLLOW)
                guard fd >= 0 else { throw ArchiveFailure.unsafePath(path) }
                let input = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                defer { try? input.close() }
                var info = stat()
                guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else { throw ArchiveFailure.unsafePath(path) }
                let size = UInt64(info.st_size)
                guard size <= ArchiveSafety.maximumExpandedBytes - total else { throw ArchiveFailure.capacity }
                total += size
                if let capacity = try directory.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity,
                   UInt64(max(0, capacity)) < size + 16 * 1024 * 1024 { throw ArchiveFailure.capacity }
                guard fm.createFile(atPath: output.path, contents: nil) else { throw ArchiveFailure.capacity }
                let target = try FileHandle(forWritingTo: output)
                defer { try? target.close() }
                var written: UInt64 = 0
                while true {
                    try Task.checkCancellation()
                    let data = try input.read(upToCount: 256 * 1024) ?? Data()
                    if data.isEmpty { break }
                    guard UInt64(data.count) <= size - written else { throw ArchiveFailure.malformed("The source file changed while being copied.") }
                    try target.write(contentsOf: data)
                    written += UInt64(data.count)
                }
                guard written == size else { throw ArchiveFailure.malformed("The source file changed while being copied.") }
                try target.synchronize()
                items.append(PackingItem(url: output, path: path, size: size, isDirectory: false))
            }
        }
        _ = try ArchiveSafety.validate(entries: items.map(\.entry), archiveBytes: 0)
        return items
    }
}

enum ArchivePacker {
    static func create(sources: [PackingSource], format: PackingFormat, name: String, in outputRoot: URL,
                       progress: @Sendable (UInt64, UInt64) -> Void = { _, _ in }) throws -> URL {
        guard !sources.isEmpty, !name.contains("/"), !name.contains("\\") else { throw ArchiveFailure.unsafePath(name) }
        _ = try ArchiveSafety.safeRelativePath(name)
        let filename = name + "." + format.rawValue
        _ = try ArchiveSafety.safeRelativePath(filename)
        let items = sources.flatMap(\.items)
        guard items.reduce(0, { $0 + $1.path.utf8.count }) <= 32 * 1024 * 1024 else { throw ArchiveFailure.capacity }
        let total = try ArchiveSafety.validate(entries: items.map(\.entry), archiveBytes: 0)
        try Task.checkCancellation()
        let values = try outputRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .volumeAvailableCapacityKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw DestinationFailure.invalidDirectory }
        // Include per-entry overhead and headroom; disk-write failures still roll back.
        let overhead = UInt64(items.count) * 8192 + 16 * 1024 * 1024
        if let capacity = values.volumeAvailableCapacity, UInt64(max(0, capacity)) < total + overhead { throw ArchiveFailure.capacity }
        let stage = outputRoot.appendingPathComponent(".ArchiveDesk-Pack-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        do {
        let file = stage.appendingPathComponent(filename)
        let fd = Darwin.open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw ArchiveFailure.capacity }
        let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? output.close() }
        guard let locale = archivedesk_codec_enter_utf8_locale() else { throw ArchiveFailure.capacity }
        defer { archivedesk_codec_leave_utf8_locale(locale) }
        guard let writer = archive_write_new() else { throw ArchiveFailure.capacity }
        defer { archive_write_free(writer) }
        func check(_ status: Int32) throws {
            guard status == ARCHIVE_OK else {
                throw ArchiveFailure.malformed(archive_error_string(writer).map { String(cString: $0) } ?? "Archive creation failed.")
            }
        }
        if format == .zip {
            try check(archive_write_set_format_zip(writer))
            try check(archive_write_set_options(writer, "zip:compression=deflate"))
        } else { try check(archive_write_set_format_pax_restricted(writer)) }
        try check(archive_write_open_fd(writer, fd))
        var processed: UInt64 = 0
        var lastProgressTime = Date.timeIntervalSinceReferenceDate
        progress(0, total)
        for item in items {
            try Task.checkCancellation()
            guard let entry = archive_entry_new() else { throw ArchiveFailure.capacity }
            defer { archive_entry_free(entry) }
            item.path.withCString { archive_entry_set_pathname_utf8(entry, $0) }
            archive_entry_set_filetype(entry, item.isDirectory ? UInt32(S_IFDIR) : UInt32(S_IFREG))
            archive_entry_set_perm(entry, item.isDirectory ? 0o755 : 0o644)
            archive_entry_set_size(entry, Int64(item.size))
            try check(archive_write_header(writer, entry))
            if !item.isDirectory {
                let inputFD = Darwin.open(item.url.path, O_RDONLY | O_NOFOLLOW)
                guard inputFD >= 0 else { throw ArchiveFailure.unsafePath(item.path) }
                let input = FileHandle(fileDescriptor: inputFD, closeOnDealloc: true)
                defer { try? input.close() }
                var fileBytes: UInt64 = 0
                while true {
                    try Task.checkCancellation()
                    let data = try input.read(upToCount: 256 * 1024) ?? Data()
                    if data.isEmpty { break }
                    guard UInt64(data.count) <= item.size - fileBytes else { throw ArchiveFailure.malformed("The packing snapshot changed.") }
                    try data.withUnsafeBytes { buffer in
                        var offset = 0
                        while offset < data.count {
                            try Task.checkCancellation()
                            let count = archive_write_data(writer, buffer.baseAddress!.advanced(by: offset), data.count - offset)
                            guard count > 0 else { throw ArchiveFailure.malformed("Writing archive data failed.") }
                            offset += count
                        }
                    }
                    fileBytes += UInt64(data.count); processed += UInt64(data.count)
                    let now = Date.timeIntervalSinceReferenceDate
                    if now - lastProgressTime >= 0.1 {
                        progress(processed, total); lastProgressTime = now
                    }
                }
                guard fileBytes == item.size else { throw ArchiveFailure.malformed("The packing snapshot changed.") }
            }
            try check(archive_write_finish_entry(writer))
        }
        try check(archive_write_close(writer))
        try output.synchronize(); try output.close()
        try Task.checkCancellation()
        let destination = outputRoot.appendingPathComponent("Packed-\(UUID())", isDirectory: true)
        try FileManager.default.moveItem(at: stage, to: destination)
        progress(total, total)
        return destination.appendingPathComponent(filename)
        } catch {
            let original = error
            do { try FileManager.default.removeItem(at: stage) }
            catch { throw ExtractionRollbackFailure(stagingFolder: stage.lastPathComponent, cause: original.localizedDescription, packing: true) }
            throw original
        }
    }
}

extension CoordinatedFileAccess {
    static func pack(sources: [PackingSource], format: PackingFormat, name: String, to folder: URL,
                     progress: @escaping @Sendable (UInt64, UInt64) -> Void) throws -> URL {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        _ = try DestinationPolicy.validate(folder)
        var error: NSError?
        var result: Result<URL, Error>?
        NSFileCoordinator().coordinate(writingItemAt: folder, options: [.forMerging], error: &error) { writable in
            result = Result {
                _ = try DestinationPolicy.validate(writable)
                return try ArchivePacker.create(sources: sources, format: format, name: name, in: writable, progress: progress)
            }
        }
        if let error { throw error }
        guard let result else { throw DestinationFailure.invalidDirectory }
        return try result.get()
    }
}
