import Foundation
import CryptoKit

@main
struct MediaPackingVerification {
    static func digest(_ url: URL) throws -> SHA256.Digest {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 256 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize()
    }
    static func main() throws {
        guard CommandLine.arguments.count == 6 else { fatalError("Pass private output folder and video/audio/text/image paths") }
        let fm = FileManager.default
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        guard !fm.fileExists(atPath: root.path) else { fatalError("Refusing to replace existing fixture folder") }
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        var success = false
        defer { if !success { try? fm.removeItem(at: root) } }
        let names = ["video.mp4", "song.flac", "OST1.log", "cover.jpeg"]
        let originals = CommandLine.arguments.dropFirst(2).map { URL(fileURLWithPath: $0) }
        var sources: [PackingSource] = []
        defer { for source in sources { try? fm.removeItem(at: source.snapshotDirectory) } }
        for (url, name) in zip(originals, names) {
            sources.append(try PackingInput.snapshot(url, name: name, coordinated: false, temporaryRoot: root))
        }
        let expected = try originals.map(digest)
        for format in PackingFormat.allCases {
            let progress = ProgressMailbox()
            let packed = try ArchivePacker.create(sources: sources, format: format, name: "PreviewSamples", in: root,
                progress: { progress.update($0, $1) })
            precondition(progress.read().bytes == sources.reduce(0) { $0 + $1.bytes })
            let archive = try ArchiveContainer.open(url: packed)
            precondition(archive.entries.count == 4)
            let output = try archive.extract(outputRoot: root)
            defer { try? fm.removeItem(at: output) }
            for (index, name) in names.enumerated() {
                let file = output.appendingPathComponent(name)
                let actual = try digest(file)
                precondition(actual == expected[index], "Archive round-trip must preserve original bytes")
                let entry = archive.entries.first { $0.path == name }!
                if name.hasSuffix(".log") {
                    let text = try archive.previewText(entry)
                    let originalText = ArchiveTextPreview.decode(try Data(contentsOf: originals[index]))
                    precondition(text != nil && text == originalText, "UTF-16 real log must preview unchanged")
                } else {
                    let decoder = try ArchiveMediaDecoder(url: file)
                    guard let event = try decoder.next() else { fatalError("No decoded frame") }
                    precondition(!event.bytes.isEmpty)
                    if index == 0 { precondition(decoder.info.videoCodec == "libdav1d" && decoder.info.audioCodec == "aac") }
                    if index == 1 { precondition(decoder.info.audioCodec == "flac") }
                    if index == 3 { precondition(event.kind == 1 && event.width == 900 && event.height == 900) }
                }
            }
            print("PASS: \(format.rawValue.uppercased()) multi-source packing, complete progress, four original SHA-256 matches, UTF-16 log and selected media decode")
            if format == .zip {
                // The only retained private fixture is needed by the native UI
                // test. It is outside source/resources and never distributed.
                try fm.moveItem(at: packed, to: root.appendingPathComponent("PreviewSamples.zip"))
                try fm.removeItem(at: packed.deletingLastPathComponent())
            } else { try fm.removeItem(at: packed.deletingLastPathComponent()) }
        }
        let after = try originals.map(digest)
        precondition(after.map(Array.init) == expected.map(Array.init), "Read-only originals unchanged")
        success = true
        print("PASS: original files unchanged; input snapshots and extracted outputs removed")
    }
}
