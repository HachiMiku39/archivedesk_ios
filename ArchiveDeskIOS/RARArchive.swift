import Foundation
import CArchiveRar

enum RARFailure: LocalizedError {
    case passwordRequired, passwordOrDamage, unsupported, malformed
    var errorDescription: String? {
        switch self {
        case .passwordRequired: String(localized: "Enter the archive password to continue.")
        case .passwordOrDamage: String(localized: "The password is incorrect, or the RAR archive is damaged.")
        case .unsupported: String(localized: "This RAR feature is not supported. Multi-volume archives are not available.")
        case .malformed: String(localized: "The RAR archive could not be read safely.")
        }
    }
}

private func rarContinue(_ context: UnsafeMutableRawPointer?) -> Int32 { Task.isCancelled ? 0 : 1 }
private func checkRAR(_ status: Int32, udf: Bool = false) throws {
    if udf && ![0, 4, 5, 7].contains(status) {
        throw ArchiveFailure.malformed(String(localized: "The UDF image is damaged, unsupported, or exceeds the safe metadata limits. This is not a disk-space error."))
    }
    switch status {
    case 0: return
    case 1: throw RARFailure.passwordRequired
    case 2: throw RARFailure.passwordOrDamage
    case 3: throw RARFailure.unsupported
    case 4: throw CancellationError()
    case 5: throw ArchiveFailure.memoryLimit
    case 7: throw ArchiveFailure.resourceLimit("100,000 archive entries")
    default: throw RARFailure.malformed
    }
}
private func withRARPassword<T>(_ password: String?, _ body: (UnsafePointer<CChar>?) throws -> T) throws -> T {
    if let password {
        guard !password.contains("\0"), password.utf8.count <= 1024 else { throw RARFailure.passwordOrDamage }
        return try password.withCString(body)
    }
    return try body(nil)
}

private final class RAROutput {
    let body: (Data) throws -> Void
    var error: Error?
    init(_ body: @escaping (Data) throws -> Void) { self.body = body }
}
private func rarWrite(_ context: UnsafeMutableRawPointer?, _ bytes: UnsafeRawPointer?, _ count: Int) -> Int32 {
    guard let context, let bytes else { return 1 }
    let output = Unmanaged<RAROutput>.fromOpaque(context).takeUnretainedValue()
    do {
        try Task.checkCancellation()
        try autoreleasepool { try output.body(Data(bytes: bytes, count: count)) }
        return 0
    } catch { output.error = error; return 1 }
}

/// The bridge handle, decoder keys and callbacks stay on this synchronous
/// thread. No password is stored in the archive model or between tasks.
private final class RARReader {
    let pointer: UnsafeMutableRawPointer
    let udf: Bool
    init(url: URL, password: String?, udf: Bool = false) throws {
        self.udf = udf
        var status: Int32 = 0
        let opened = try withRARPassword(password) { secret in
            url.path.withCString { udf ? adr_open_udf($0, rarContinue, nil, &status) : adr_open($0, secret, rarContinue, nil, &status) }
        }
        try checkRAR(status, udf: udf)
        guard let opened else { throw RARFailure.malformed }
        pointer = opened
    }
    deinit { adr_close(pointer) }
    var headersEncrypted: Bool { adr_headers_encrypted(pointer) != 0 }
    var formatName: String { udf ? "UDF" : adr_version(pointer) == 5 ? "RAR5" : "RAR4" }
    func entry(_ index: Int) throws -> ArchiveEntry {
        var path = [CChar](repeating: 0, count: 4096)
        var value = ADREntry()
        try checkRAR(adr_entry(pointer, UInt32(index), &path, path.count, &value), udf: udf)
        guard let decoded = path.withUnsafeBufferPointer({ String(validatingCString: $0.baseAddress!) }), value.unsafe == 0 else {
            throw ArchiveFailure.unsafePath("RAR entry")
        }
        let name = decoded + (value.directory != 0 && !decoded.hasSuffix("/") ? "/" : "")
        _ = try ArchiveSafety.safeRelativePath(name)
        return ArchiveEntry(id: index, path: name, compressedSize: value.packed, uncompressedSize: value.size,
                            crc32: value.crc, compressionMethod: UInt16.max, localHeaderOffset: 0,
                            flags: value.encrypted != 0 ? 1 : 0, nativeFormat: formatName,
                            hasCRC: value.has_crc != 0 && value.encrypted == 0, passwordDecodable: true)
    }
    func stream(_ expected: ArchiveEntry, password: String?, body: @escaping (Data) throws -> Void) throws {
        let actual = try entry(expected.id)
        guard actual.path == expected.path, actual.uncompressedSize == expected.uncompressedSize,
              !actual.isDirectory, actual.isExtractable else { throw RARFailure.malformed }
        let output = RAROutput(body)
        let result = try withRARPassword(password) {
            adr_extract(pointer, UInt32(expected.id), expected.uncompressedSize, $0, rarWrite, Unmanaged.passUnretained(output).toOpaque())
        }
        if let error = output.error { throw error }
        try checkRAR(result, udf: udf)
    }
}

struct RARArchive: Sendable {
    let url: URL
    let entries: [ArchiveEntry]
    let headersEncrypted: Bool
    let formatName: String
    var isUDF: Bool = false
    static func open(url: URL, password: String? = nil, udf: Bool = false) throws -> Self {
        let reader = try RARReader(url: url, password: password, udf: udf)
        var entries: [ArchiveEntry] = []
        var nameBytes = 0
        for index in 0..<Int(adr_count(reader.pointer)) {
            try Task.checkCancellation()
            let entry = try reader.entry(index)
            nameBytes += entry.path.utf8.count
            guard nameBytes <= 32 * 1024 * 1024 else { throw ArchiveFailure.resourceLimit("32 MiB RAR path metadata") }
            entries.append(entry)
        }
        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        _ = try ArchiveSafety.validate(entries: entries, archiveBytes: UInt64(max(0, bytes)))
        return Self(url: url, entries: entries, headersEncrypted: reader.headersEncrypted, formatName: reader.formatName, isUDF: udf)
    }
    func requiresPassword(_ entry: ArchiveEntry) -> Bool { headersEncrypted || entry.isEncrypted }
    func previewText(_ entry: ArchiveEntry, password: String? = nil) throws -> String? {
        guard !entry.isDirectory, entry.uncompressedSize <= 256 * 1024,
              ["txt", "md", "json", "xml", "csv", "log", "swift", "plist", "yaml", "yml"].contains((entry.path as NSString).pathExtension.lowercased()) else { return nil }
        if requiresPassword(entry), password == nil { throw RARFailure.passwordRequired }
        let reader = try RARReader(url: url, password: password, udf: isUDF)
        var bytes = Data()
        try reader.stream(entry, password: password) { bytes.append($0) }
        return ArchiveTextPreview.decode(bytes)
    }
    func extract(paths: Set<String>? = nil, outputRoot: URL, createOutputRoot: Bool = true, password: String? = nil,
                 progress: @escaping ArchiveProgress = { _, _ in }) throws -> URL {
        let selected = entries.filter { paths == nil || paths!.contains($0.path) }
        guard !selected.isEmpty, selected.allSatisfy(\.isExtractable) else { throw RARFailure.unsupported }
        if selected.contains(where: requiresPassword), password == nil { throw RARFailure.passwordRequired }
        let total = try ArchiveSafety.validate(entries: selected, archiveBytes: 0)
        let meter = ExtractionProgress(total: total, callback: progress)
        try Task.checkCancellation()
        if createOutputRoot { try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true) }
        let values = try outputRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .volumeAvailableCapacityKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw DestinationFailure.invalidDirectory }
        try StorageBudget.require(total + 16 * 1024 * 1024, at: outputRoot)
        let stage = outputRoot.appendingPathComponent(".ArchiveDesk-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        do {
            // Reuse one task-local handle; reopening the whole image per file
            // would repeatedly index hundreds of UDF entries on USB storage.
            let imageReader = isUDF ? try RARReader(url: url, password: nil, udf: true) : nil
            for entry in selected {
                try Task.checkCancellation()
                let file = stage.appendingPathComponent(try ArchiveSafety.outputPath(entry.path))
                if entry.isDirectory {
                    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
                } else {
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try StorageBudget.createFile(at: file)
                    let target = try FileHandle(forWritingTo: file)
                    defer { try? target.close() }
                    let reader = try imageReader ?? RARReader(url: url, password: password)
                    try reader.stream(entry, password: password) {
                        try target.write(contentsOf: $0); meter.advance($0.count)
                    }
                    try target.synchronize(); try target.close()
                }
            }
            try Task.checkCancellation()
            let final = outputRoot.appendingPathComponent("Extracted-\(UUID())", isDirectory: true)
            try FileManager.default.moveItem(at: stage, to: final)
            meter.complete()
            return final
        } catch {
            let original = error
            do { try FileManager.default.removeItem(at: stage) }
            catch { throw ExtractionRollbackFailure(stagingFolder: stage.lastPathComponent, cause: original.localizedDescription) }
            throw original
        }
    }
}
