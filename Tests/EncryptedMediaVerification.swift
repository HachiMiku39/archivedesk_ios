import Foundation
import CryptoKit

/// Private user media is supplied at runtime, never stored in the repository.
@main
struct EncryptedMediaVerification {
    static func digest(_ url: URL) throws -> SHA256.Digest {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 256 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize()
    }
    static func main() throws {
        precondition(CommandLine.arguments.count == 2)
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fm = FileManager.default
        let output = root.appendingPathComponent("Verify-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: output, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: output) }
        let password = "ArchiveDesk-Test-2026" // Disposable fixture password only.
        for name in ["Media-ZipCrypto.zip", "Media-AES.zip"] {
            let archive = try ArchiveContainer.open(url: root.appendingPathComponent(name))
            precondition(archive.entries.count == 5)
            for entry in archive.entries {
                precondition(entry.isEncrypted && archive.requiresPassword(entry) && !entry.isExtractable)
                do {
                    _ = try archive.extract(paths: [entry.path], outputRoot: output, password: password)
                    fatalError("Unsupported encrypted ZIP reached extraction")
                } catch { }
            }
            let leftovers = try fm.contentsOfDirectory(atPath: output.path)
            precondition(leftovers.isEmpty)
            print("PASS: \(name) lists five encrypted names; extraction blocked, no plaintext output")
        }
        for name in ["Media-VisibleNames.rar", "Media-HiddenNames.rar"] {
            let url = root.appendingPathComponent(name)
            let hidden = name.contains("Hidden")
            if hidden {
                do { _ = try ArchiveContainer.open(url: url); fatalError("Hidden headers opened without password") }
                catch RARFailure.passwordRequired { }
                do { _ = try ArchiveContainer.open(url: url, password: "wrong"); fatalError("Wrong header password accepted") }
                catch RARFailure.passwordOrDamage { }
            }
            let archive = try ArchiveContainer.open(url: url, password: hidden ? password : nil)
            precondition(archive.entries.count == 5)
            for entry in archive.entries {
                precondition(archive.requiresPassword(entry))
                for rejected in [nil, "wrong"] as [String?] {
                    do {
                        _ = try archive.extract(paths: [entry.path], outputRoot: output, password: rejected)
                        fatalError("Missing/wrong password accepted")
                    } catch RARFailure.passwordRequired {
                        precondition(rejected == nil)
                    } catch RARFailure.passwordOrDamage {
                        precondition(rejected != nil)
                    }
                    let leftovers = try fm.contentsOfDirectory(atPath: output.path)
                    precondition(leftovers.isEmpty, "Failed decryption must roll back")
                }
                let unpacked = try archive.extract(paths: [entry.path], outputRoot: output, password: password)
                let file = unpacked.appendingPathComponent(entry.path)
                let expected = try digest(root.appendingPathComponent("encrypted-input").appendingPathComponent(entry.path))
                let actual = try digest(file)
                precondition(actual == expected)
                if ArchivePreviewKind.forPath(entry.path) == .text {
                    let text = try archive.previewText(entry, password: password)
                    precondition(text != nil)
                } else {
                    // Mirrors the app: decoder is created only after complete,
                    // authenticated archive extraction and integrity checking.
                    let decoder = try ArchiveMediaDecoder(url: file, videoMaxEdge: entry.path.hasSuffix("mp4") ? 640 : 1280)
                    let firstFrame = try decoder.next()
                    precondition(firstFrame != nil)
                    if entry.path.hasSuffix(".flac") && entry.path != "song.flac" {
                        let original = try ArchiveMediaDecoder(url: root.appendingPathComponent("encrypted-input").appendingPathComponent(entry.path))
                        precondition(decoder.info.tags.map { [$0.key, $0.value] } == original.info.tags.map { [$0.key, $0.value] })
                        let cover = try decoder.artwork()
                        let originalCover = try original.artwork()
                        precondition(cover != nil && cover?.bytes == originalCover?.bytes)
                    }
                }
                try fm.removeItem(at: unpacked)
            }
            print("PASS: \(name) password gating, wrong-password rollback, five SHA-256 matches and post-decryption media/tag/art decoding")
        }
    }
}
