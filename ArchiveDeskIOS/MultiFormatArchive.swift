
import Foundation
import CArchive

/// Reader instances never escape their synchronous creating thread. The vendor
/// build caps allocations and disables XZ threads; no helper program is enabled.
final class NativeArchiveReader {
    let pointer: OpaquePointer
    let url: URL
    private let buffer: UnsafeMutableRawPointer
    private let locale: UnsafeMutableRawPointer
    init(url: URL, zipHeaderCharset: String? = nil) throws {
        self.url = url
        guard let locale = archivedesk_codec_enter_utf8_locale() else { throw ArchiveFailure.capacity }
        guard let pointer = archive_read_new() else {
            archivedesk_codec_leave_utf8_locale(locale)
            throw ArchiveFailure.capacity
        }
        self.locale = locale
        self.pointer = pointer
        self.buffer = UnsafeMutableRawPointer.allocate(byteCount: 256 * 1024, alignment: 16)
        // Register only formats/filters with compiled in-process codecs.
        for result in [archive_read_support_filter_none(pointer), archive_read_support_filter_gzip(pointer),
                       archive_read_support_filter_bzip2(pointer), archive_read_support_filter_xz(pointer),
                       archive_read_support_filter_lzma(pointer), archive_read_support_format_zip_seekable(pointer),
                       archive_read_support_format_7zip(pointer), archive_read_support_format_rar(pointer),
                       archive_read_support_format_rar5(pointer), archive_read_support_format_tar(pointer),
                       archive_read_support_format_iso9660(pointer)] {
            try check(result)
        }
        if ["gz", "gzip", "bz2", "xz", "lzma"].contains(url.pathExtension.lowercased()) {
            try check(archive_read_support_format_raw(pointer))
        }
        if let zipHeaderCharset {
            try check(archive_read_set_format_option(pointer, "zip", "hdrcharset", zipHeaderCharset))
        }
        try Task.checkCancellation()
        try check(url.path.withCString { archive_read_open_filename(pointer, $0, 256 * 1024) })
        // Once every stored property is initialized, Swift invokes deinit if
        // this initializer throws. Manual cleanup here would double-free.
    }
    deinit {
        archive_read_free(pointer)
        buffer.deallocate()
        archivedesk_codec_leave_utf8_locale(locale)
    }
    var formatName: String {
        if archive_format(pointer) == ARCHIVE_FORMAT_RAW,
           let name = archive_filter_name(pointer, 0) {
            return String(cString: name)
        }
        return archive_format_name(pointer).map { String(cString: $0) } ?? "Archive"
    }
    func check(_ result: Int32) throws {
        guard result == ARCHIVE_OK else {
            let message = archive_error_string(pointer).map { String(cString: $0) } ?? "Unsupported or damaged archive."
            throw ArchiveFailure.malformed(message)
        }
    }
    func next() throws -> OpaquePointer? {
        try Task.checkCancellation()
        var entry: OpaquePointer?
        let status = archive_read_next_header(pointer, &entry)
        if status == ARCHIVE_EOF { return nil }
        try check(status)
        return entry
    }
    func path(_ entry: OpaquePointer) throws -> String {
        if archive_format(pointer) == ARCHIVE_FORMAT_RAW {
            guard archive_filter_code(pointer, 0) != ARCHIVE_FILTER_NONE else {
                throw ArchiveFailure.unsupported("This is not a recognized compressed stream.")
            }
            return url.deletingPathExtension().lastPathComponent
        }
        guard let pointer = archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry),
              let path = String(validatingCString: pointer) else {
            throw ArchiveFailure.malformed("The archive filename cannot be decoded safely.")
        }
        // TAR/ISO conventionally prefix relative entries with "./". Remove
        // only leading current-directory components; never collapse "..".
        var relative = path
        while relative.hasPrefix("./") { relative.removeFirst(2) }
        return relative
    }
    func metadata(_ entry: OpaquePointer, id: Int) throws -> ArchiveEntry {
        var path = try path(entry)
        let directory = archivedesk_entry_is_directory(entry) != 0
        if directory && !path.hasSuffix("/") { path += "/" }
        let special = archivedesk_entry_is_regular(entry) == 0 && !directory
            || archive_entry_symlink(entry) != nil || archive_entry_hardlink(entry) != nil
        guard !special else { throw ArchiveFailure.unsafePath(path) }
        _ = try ArchiveSafety.safeRelativePath(path)
        let signedSize = archive_entry_size(entry)
        guard signedSize >= 0 else { throw ArchiveFailure.malformed("Invalid archive entry size.") }
        var size = directory ? 0 : UInt64(signedSize)
        // Raw streams have no declared output length. Scan bounded chunks now,
        // then re-open the immutable snapshot when previewing or extracting.
        if !directory && archive_entry_size_is_set(entry) == 0 {
            size = try consume(limit: ArchiveSafety.maximumExpandedBytes) { _ in }
        } else {
            try check(archive_read_data_skip(pointer))
        }
        return ArchiveEntry(id: id, path: path, compressedSize: 0, uncompressedSize: size,
                            crc32: 0, compressionMethod: UInt16.max, localHeaderOffset: 0,
                            flags: archive_entry_is_encrypted(entry) == 1 ? 1 : 0,
                            nativeFormat: formatName, hasCRC: false)
    }
    @discardableResult
    func consume(limit: UInt64, body: (Data) throws -> Void) throws -> UInt64 {
        var count: UInt64 = 0
        while true {
            try Task.checkCancellation()
            let size = archive_read_data(pointer, buffer, 256 * 1024)
            if size < 0 {
                let message = archive_error_string(pointer).map { String(cString: $0) } ?? "Archive decoding failed."
                throw ArchiveFailure.malformed(message)
            }
            if size == 0 { break }
            guard UInt64(size) <= limit - count else { throw ArchiveFailure.capacity }
            count += UInt64(size)
            try autoreleasepool { try body(Data(bytes: buffer, count: size)) }
        }
        return count
    }
    static func stream(_ expected: ArchiveEntry, from url: URL, body: (Data) throws -> Void) throws {
        // Match the strict ZIP parser's unflagged CP437 default. Native ZIP
        // keeps its UTF-8 flag/Unicode extra handling; do not guess locale names.
        let reader = try NativeArchiveReader(url: url, zipHeaderCharset: expected.nativeFormat == nil ? "CP437" : nil)
        while let entry = try reader.next() {
            let path = try reader.path(entry)
            if archivedesk_entry_is_directory(entry) != 0 && (path.isEmpty || path == ".") {
                // A harmless archive-root directory is not an output entry.
                guard archive_entry_symlink(entry) == nil, archive_entry_hardlink(entry) == nil else {
                    throw ArchiveFailure.unsafePath(path)
                }
                try reader.check(archive_read_data_skip(reader.pointer))
                continue
            }
            if path == expected.path {
                guard archivedesk_entry_is_regular(entry) != 0,
                      archive_entry_symlink(entry) == nil, archive_entry_hardlink(entry) == nil,
                      archive_entry_is_encrypted(entry) != 1 else { throw ArchiveFailure.unsafePath(path) }
                if archive_entry_size_is_set(entry) != 0 {
                    guard archive_entry_size(entry) >= 0, UInt64(archive_entry_size(entry)) == expected.uncompressedSize else {
                        throw ArchiveFailure.malformed("Archive metadata changed between listing and extraction.")
                    }
                }
                var crc: UInt32 = 0
                let size = try reader.consume(limit: expected.uncompressedSize) { chunk in
                    crc = chunk.withUnsafeBytes { CRC32.update(crc, bytes: $0) }
                    try body(chunk)
                }
                guard size == expected.uncompressedSize else { throw ArchiveFailure.malformed("The archive output length is incorrect.") }
                if expected.hasCRC && crc != expected.crc32 { throw ArchiveFailure.crcMismatch(path) }
                try Task.checkCancellation()
                return
            }
            try reader.check(archive_read_data_skip(reader.pointer))
        }
        throw ArchiveFailure.malformed("The selected archive entry could not be found.")
    }
}

struct MultiFormatArchive: Sendable {
    let url: URL
    let entries: [ArchiveEntry]
    let formatName: String
    static func open(url: URL) throws -> Self {
        let reader = try NativeArchiveReader(url: url)
        var entries: [ArchiveEntry] = []
        var nameBytes = 0
        var headers = 0
        while let entry = try reader.next() {
            guard headers < ArchiveSafety.maximumEntries else { throw ArchiveFailure.capacity }
            headers += 1
            let path = try reader.path(entry)
            if archivedesk_entry_is_directory(entry) != 0 && (path.isEmpty || path == ".") {
                guard archive_entry_symlink(entry) == nil, archive_entry_hardlink(entry) == nil else {
                    throw ArchiveFailure.unsafePath(path)
                }
                try reader.check(archive_read_data_skip(reader.pointer))
                continue
            }
            guard entries.count < ArchiveSafety.maximumEntries else { throw ArchiveFailure.capacity }
            let value = try reader.metadata(entry, id: entries.count)
            nameBytes += value.path.utf8.count
            guard nameBytes <= 32 * 1024 * 1024 else { throw ArchiveFailure.capacity }
            entries.append(value)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        _ = try ArchiveSafety.validate(entries: entries, archiveBytes: handle.seekToEnd())
        return Self(url: url, entries: entries, formatName: reader.formatName)
    }
    func previewText(_ entry: ArchiveEntry) throws -> String? {
        guard entry.isExtractable, !entry.isDirectory, entry.uncompressedSize <= 256 * 1024,
              ["txt", "md", "json", "xml", "csv", "log", "swift", "plist", "yaml", "yml"].contains((entry.path as NSString).pathExtension.lowercased()) else { return nil }
        var data = Data()
        try NativeArchiveReader.stream(entry, from: url) { data.append($0) }
        return String(data: data, encoding: .utf8)
    }
    func extract(paths: Set<String>? = nil, outputRoot: URL, createOutputRoot: Bool = true,
                 progress: @escaping ArchiveProgress = { _, _ in }) throws -> URL {
        let selected = entries.filter { paths == nil || paths!.contains($0.path) }
        guard !selected.isEmpty, selected.allSatisfy(\.isExtractable) else {
            throw ArchiveFailure.unsupported("The selection contains encrypted or unsupported entries.")
        }
        let total = try ArchiveSafety.validate(entries: selected, archiveBytes: 0)
        let meter = ExtractionProgress(total: total, callback: progress)
        try Task.checkCancellation()
        if createOutputRoot { try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true) }
        let values = try outputRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .volumeAvailableCapacityKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw DestinationFailure.invalidDirectory }
        if let capacity = values.volumeAvailableCapacity, UInt64(max(0, capacity)) < total + 16 * 1024 * 1024 { throw ArchiveFailure.capacity }
        let staging = outputRoot.appendingPathComponent(".ArchiveDesk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            for entry in selected {
                try Task.checkCancellation()
                let output = staging.appendingPathComponent(try ArchiveSafety.outputPath(entry.path))
                if entry.isDirectory {
                    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                    continue
                }
                try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard FileManager.default.createFile(atPath: output.path, contents: nil) else { throw ArchiveFailure.capacity }
                let handle = try FileHandle(forWritingTo: output)
                do {
                    try NativeArchiveReader.stream(entry, from: url) {
                        try handle.write(contentsOf: $0); meter.advance($0.count)
                    }
                    try handle.synchronize(); try handle.close()
                } catch { try? handle.close(); throw error }
            }
            try Task.checkCancellation()
            let final = outputRoot.appendingPathComponent("Extracted-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.moveItem(at: staging, to: final)
            meter.complete()
            return final
        } catch {
            let original = error
            do { try FileManager.default.removeItem(at: staging) }
            catch { throw ExtractionRollbackFailure(stagingFolder: staging.lastPathComponent, cause: original.localizedDescription) }
            throw original
        }
    }
}
