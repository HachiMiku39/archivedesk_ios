import Foundation
import CArchive
import Darwin

@main
enum FormatVerification {
    static func main() async throws {
        let fixtures = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("work/format-fixtures")
        let expected = try Data(contentsOf: fixtures.appendingPathComponent("input/Notes.md"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveDesk-Formats-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["sample.7z", "lzma.7z", "deflate.zip", "sample.tar", "sample.tar.gz", "sample.tar.bz2", "sample.tar.xz", "Notes.md.gz", "Notes.md.bz2", "Notes.md.xz", "Notes.md.lzma"] {
            let originalLocale = uselocale(nil)
            let archive = try ArchiveContainer.open(url: fixtures.appendingPathComponent(name))
            if name == "deflate.zip" { precondition(archive.entries.first(where: { $0.path == "Notes.md" })?.compressionMethod == 8) }
            let note = try archive.entries.first(where: { $0.path == "Notes.md" }).unwrap("Missing Notes.md: \(name)")
            let preview = try archive.previewText(note)
            precondition(preview == String(data: expected, encoding: .utf8), "Preview \(name)")
            let progress = ProgressMailbox()
            let output = try archive.extract(outputRoot: root, progress: { progress.update($0, $1) })
            precondition(progress.read().bytes == archive.entries.reduce(0) { $0 + $1.uncompressedSize }, "Decoded-output progress: \(name)")
            let bytes = try Data(contentsOf: output.appendingPathComponent("Notes.md"))
            precondition(bytes == expected, "Bytes \(name)")
            if ["sample.7z", "deflate.zip"].contains(name) {
                for filename in ["中文.txt", "日本語.txt"] {
                    precondition(archive.entries.contains(where: { $0.path == filename }), "Unicode index")
                    let original = try Data(contentsOf: fixtures.appendingPathComponent("input/" + filename))
                    let decoded = try Data(contentsOf: output.appendingPathComponent(filename))
                    precondition(decoded == original, "Unicode filename and bytes")
                }
            }
            precondition(archivedesk_codec_live_bytes() == 0, "Leaked decoder allocation: \(name)")
            precondition(uselocale(nil) == originalLocale, "Thread locale restored")
            print("PASS: \(name) — \(archive.formatName), listing, UTF-8 preview, extraction and released allocations")
        }
        var legacy = try Data(contentsOf: fixtures.appendingPathComponent("deflate.zip"))
        let central = legacy.range(of: Data([0x50, 0x4b, 0x01, 0x02]))!.lowerBound
        legacy[30] = 0x82; legacy[central + 46] = 0x82
        legacy[7] &= 0xf7; legacy[central + 9] &= 0xf7
        let legacyURL = root.appendingPathComponent("legacy-deflate.zip")
        try legacy.write(to: legacyURL)
        let legacyArchive = try ArchiveContainer.open(url: legacyURL)
        let legacyEntry = try legacyArchive.entries.first(where: { $0.path == "éotes.md" }).unwrap("CP437 Deflate name")
        let legacyPreview = try legacyArchive.previewText(legacyEntry)
        precondition(legacyPreview == String(data: expected, encoding: .utf8))
        let legacyOutput = try legacyArchive.extract(paths: [legacyEntry.path], outputRoot: root)
        let legacyBytes = try Data(contentsOf: legacyOutput.appendingPathComponent(legacyEntry.path))
        precondition(legacyBytes == expected && archivedesk_codec_live_bytes() == 0)
        print("PASS: CP437 Deflate filename, verified preview and output bytes")
        for name in ["rar4.rar", "rar5.rar", "rar5-solid.rar", "sample.iso"] {
            let archive = try ArchiveContainer.open(url: fixtures.appendingPathComponent(name))
            let output = try archive.extract(outputRoot: root)
            let files = archive.entries.filter { !$0.isDirectory }
            precondition(!files.isEmpty)
            for entry in files {
                let data = try Data(contentsOf: output.appendingPathComponent(entry.path))
                precondition(data.count == entry.uncompressedSize)
                if name == "rar4.rar" {
                    precondition(CRC32.checksum(data) == (entry.path == "random_data.bin" ? 0xb5c45cbe : 0x3435594d))
                }
                if name == "sample.iso" { precondition(data == Data("hello\n".utf8)) }
                if name.hasPrefix("rar5") {
                    let magic = name == "rar5.rar" ? 0 : Int(entry.path.filter(\.isNumber))!
                    for index in 0..<(data.count / 4) {
                        let k = index + 1, value = UInt32(max(0, k * k - 3 * k + 1 + magic))
                        let offset = index * 4
                        precondition(Array(data[offset..<(offset + 4)]) == [UInt8(value & 255), UInt8((value >> 8) & 255), UInt8((value >> 16) & 255), UInt8(value >> 24)])
                    }
                }
            }
            precondition(archivedesk_codec_live_bytes() == 0)
            print("PASS: \(name) — \(archive.formatName), \(files.count) extracted files; bytes verified against independent vectors")
        }
        precondition(archivedesk_codec_malloc(129 * 1024 * 1024) == nil, "Single allocation cap")
        let allocation = archivedesk_codec_malloc(128 * 1024 * 1024)
        precondition(allocation != nil)
        let second = archivedesk_codec_malloc(128 * 1024 * 1024)
        precondition(second != nil && archivedesk_codec_malloc(1) == nil, "Live allocation budget")
        archivedesk_codec_free(second)
        archivedesk_codec_free(allocation)
        precondition(archivedesk_codec_live_bytes() == 0)
        print("PASS: decoder allocation cap and accounting")
        for name in ["traversal.tar", "absolute.tar", "case-alias.tar", "unicode-alias.tar", "prefix-conflict.tar", "symlink.tar", "hardlink.tar", "fifo.tar", "rar-links.rar"] {
            do {
                _ = try ArchiveContainer.open(url: fixtures.appendingPathComponent(name))
                fatalError("Accepted unsafe archive: \(name)")
            } catch { precondition(archivedesk_codec_live_bytes() == 0) }
            print("PASS: safely rejected \(name)")
        }
        let relative = try ArchiveContainer.open(url: fixtures.appendingPathComponent("current-dir.tar"))
        precondition(relative.entries.first?.path == "Notes.md", "Safe leading ./ normalization")
        for name in ["sample.7z", "deflate.zip", "Notes.md.xz"] {
            let destination = root.appendingPathComponent("damaged-" + name)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let keep = destination.appendingPathComponent("keep.txt")
            try expected.write(to: keep)
            var damaged = try Data(contentsOf: fixtures.appendingPathComponent(name))
            damaged[name == "sample.7z" ? 55 : (name == "deflate.zip" ? 60 : 40)] ^= 0xff
            let input = root.appendingPathComponent(name)
            try damaged.write(to: input)
            do {
                let archive = try ArchiveContainer.open(url: input)
                _ = try archive.extract(outputRoot: destination)
                fatalError("Accepted corrupt archive: \(name)")
            } catch {
                let items = try FileManager.default.contentsOfDirectory(atPath: destination.path)
                precondition(items == ["keep.txt"], "Owned staging rolled back; existing files preserved")
                precondition(archivedesk_codec_live_bytes() == 0)
            }
            print("PASS: damaged \(name) rejected, staging cleaned, existing file preserved")
        }
        for name in ["plain.txt", "fake.gz", "missing.7z"] {
            let input = root.appendingPathComponent(name)
            if name != "missing.7z" { try expected.write(to: input) }
            do {
                _ = try ArchiveContainer.open(url: input)
                fatalError("Accepted non-archive: \(name)")
            } catch { precondition(archivedesk_codec_live_bytes() == 0) }
            print("PASS: \(name) rejected without double cleanup")
        }
        let cancelURL = fixtures.appendingPathComponent("sample.7z")
        let cancellation = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            do { _ = try NativeArchiveReader(url: cancelURL); return false }
            catch is CancellationError { return archivedesk_codec_live_bytes() == 0 }
            catch { return false }
        }
        cancellation.cancel()
        let cancelledCleanly = await cancellation.value
        precondition(cancelledCleanly, "Cancelled initializer cleaned exactly once")
        print("PASS: cancelled native initializer releases exactly once")
    }
}

private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let value = self else { throw ArchiveFailure.malformed(message) }
        return value
    }
}
