import Foundation
import CryptoKit
import CArchive
import Darwin

/// Explicit opt-in large-image verification. Never stages user data internally.
/// All generated trees live under one freshly created external-drive run folder.
@main
enum ExternalImageVerification {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 3 || args.count == 4 else {
            throw ArchiveFailure.unsupported("Usage: external-image-verification --list image | --round-trip image external-test-directory")
        }
        let input = URL(fileURLWithPath: args[2]).standardizedFileURL
        let before = try input.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let archive = try ArchiveContainer.open(url: input)
        let total = archive.entries.reduce(UInt64(0)) { $0 + $1.uncompressedSize }
        print("INDEX: \(archive.formatName), \(archive.entries.count) entries, \(total) output bytes")
        for entry in archive.entries.prefix(12) { print("ENTRY: \(entry.path), \(entry.uncompressedSize)") }
        if let largest = archive.entries.max(by: { $0.uncompressedSize < $1.uncompressedSize }) {
            print("LARGEST: \(largest.path), \(largest.uncompressedSize)")
        }
        if args[1] == "--list" { return }
        guard args.count == 4, args[1] == "--round-trip", archive.formatName == "UDF",
              archive.entries.contains(where: { $0.path.lowercased().hasSuffix("sources/install.wim") }) else {
            throw ArchiveFailure.unsupported("Require a real UDF Windows image, not its ISO9660 README stub.")
        }
        let external = URL(fileURLWithPath: args[3], isDirectory: true).standardizedFileURL
        guard external.path == "/Volumes/Ventoy/ArchiveDesk-Verification-20261006",
              external.resolvingSymlinksInPath().path == external.path else {
            throw ArchiveFailure.unsafePath("Use only the explicitly authorized external test directory")
        }
        let fm = FileManager.default
        try fm.createDirectory(at: external, withIntermediateDirectories: true)
        try StorageBudget.require(total * 4 + 512 * 1024 * 1024, at: external)
        let run = external.appendingPathComponent("run-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: run, withIntermediateDirectories: false)
        do {
            let originalHash = try hash(input)
            let extractMeter = Meter("UDF extraction")
            let extracted = try archive.extract(outputRoot: run, progress: extractMeter.report)
            try extractMeter.verify(total)
            let expected = try manifest(extracted)
            guard expected.values.filter({ !$0.directory }).count == archive.entries.filter({ !$0.isDirectory }).count else {
                throw ArchiveFailure.malformed("Missing UDF output files")
            }
            let snapshotMeter = Meter("Source snapshot")
            let source = try PackingInput.snapshot(extracted, name: "tiny11", coordinated: false,
                                                  temporaryRoot: run, progress: snapshotMeter.report)
            try snapshotMeter.verify(total)
            let packMeter = Meter("ZIP creation")
            let zipURL = try ArchivePacker.create(sources: [source], format: .zip, name: "tiny11-repacked",
                                                 in: run, progress: { packMeter.report($0, $1) })
            try packMeter.verify(total)
            let zip = try ArchiveContainer.open(url: zipURL)
            let unzipMeter = Meter("ZIP extraction")
            let unpacked = try zip.extract(outputRoot: run, progress: unzipMeter.report)
            try unzipMeter.verify(total)
            let actual = try manifest(unpacked.appendingPathComponent("tiny11", isDirectory: true))
            guard actual == expected else { throw ArchiveFailure.malformed("ZIP round-trip manifest / SHA-256 mismatch") }
            let finalHash = try hash(input)
            guard finalHash == originalHash else { throw ArchiveFailure.malformed("Original ISO hash changed") }
            var refreshedInput = input
            refreshedInput.removeAllCachedResourceValues()
            let after = try refreshedInput.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard before.fileSize == after.fileSize && before.contentModificationDate == after.contentModificationDate,
                  archivedesk_codec_live_bytes() == 0 else { throw ArchiveFailure.malformed("ISO metadata changed or codec allocation leak") }
            print("PASS: complete UDF -> ZIP -> extraction, \(expected.count) paths and SHA-256 hashes match; ISO unchanged")
            try fm.removeItem(at: run) // Only this freshly generated run, never the source or parent.
            print("CLEANUP: removed only owned run folder \(run.lastPathComponent)")
        } catch {
            let original = error
            do { try fm.removeItem(at: run) }
            catch { print("CLEANUP FAILED: owned folder \(run.path); \(error.localizedDescription)") }
            throw original
        }
    }
    private struct Record: Equatable { let directory: Bool; let bytes: UInt64; let sha256: String }
    private static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while true {
            let count = try autoreleasepool { () throws -> Int in
                let chunk = try handle.read(upToCount: 256 * 1024) ?? Data()
                hash.update(data: chunk)
                return chunk.count
            }
            if count == 0 { break }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func manifest(_ root: URL) throws -> [String: Record] {
        var result: [String: Record] = [:]
        var pending = [root]
        while let folder = pending.popLast() {
            for child in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]) {
                let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isSymbolicLink != true else { throw ArchiveFailure.unsafePath(child.lastPathComponent) }
                let relative = String(child.path.dropFirst(root.path.count + 1))
                if values.isDirectory == true {
                    result[relative] = Record(directory: true, bytes: 0, sha256: "")
                    pending.append(child)
                } else { result[relative] = Record(directory: false, bytes: UInt64(values.fileSize ?? 0), sha256: try hash(child)) }
            }
        }
        return result
    }
}

private final class Meter: @unchecked Sendable {
    let name: String
    private let lock = NSLock()
    private var bytes: UInt64 = 0, updates = 0, monotonic = true
    private var last = ProcessInfo.processInfo.systemUptime
    private let start = ProcessInfo.processInfo.systemUptime
    init(_ name: String) { self.name = name }
    func report(_ count: UInt64, _ total: UInt64) {
        lock.lock(); defer { lock.unlock() }
        if count < bytes { monotonic = false }
        bytes = count; updates += 1
        let now = ProcessInfo.processInfo.systemUptime
        if now - last >= 10 || (total > 0 && count == total) {
            let speed = Double(count) / max(0.001, now - start) / 1_048_576
            print("PROGRESS: \(name), \(count)/\(total) bytes, \(String(format: "%.1f", speed)) MiB/s average")
            fflush(stdout)
            last = now
        }
    }
    func verify(_ total: UInt64) throws {
        lock.lock(); defer { lock.unlock() }
        guard bytes == total && updates > 1 && monotonic else { throw ArchiveFailure.malformed("Incorrect or missing byte progress: " + name) }
        print("PASS: \(name) progress reached \(bytes), \(updates) callbacks")
    }
}
