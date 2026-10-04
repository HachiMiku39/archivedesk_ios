import Foundation
import CArchive

@main
enum PackingRARVerification {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("work/Packing-RAR-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("SourceA")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("空文件夹"), withIntermediateDirectories: true)
        try Data("first source 日本語\n".utf8).write(to: folder.appendingPathComponent("中文.txt"))
        let other = root.appendingPathComponent("other.txt")
        try Data("second source\n".utf8).write(to: other)
        let first = try PackingInput.snapshot(folder, name: "SourceA", coordinated: false)
        let second = try PackingInput.snapshot(other, name: "other.txt", coordinated: false)
        defer {
            try? FileManager.default.removeItem(at: first.snapshotDirectory)
            try? FileManager.default.removeItem(at: second.snapshotDirectory)
        }
        for format in PackingFormat.allCases {
            let packed = try ArchivePacker.create(sources: [first, second], format: format, name: "Mixed", in: root)
            let archive = try ArchiveContainer.open(url: packed)
            precondition(archive.entries.contains { $0.path == "SourceA/空文件夹/" })
            let dest = try archive.extract(outputRoot: root)
            let firstBytes = try Data(contentsOf: dest.appendingPathComponent("SourceA/中文.txt"))
            let otherBytes = try Data(contentsOf: dest.appendingPathComponent("other.txt"))
            precondition(firstBytes == Data("first source 日本語\n".utf8))
            precondition(otherBytes == Data("second source\n".utf8))
            print("PASS: multi-source \(format) creation / byte-for-byte round trip / empty directory")
        }
        let renamed = try PackingInput.uniqueName("OTHER.txt", used: ["other.txt"])
        precondition(renamed == "OTHER (2).txt")
        do { _ = try ArchivePacker.create(sources: [first, first], format: .zip, name: "Bad", in: root); fatalError("duplicate accepted") } catch { }
        do { _ = try ArchivePacker.create(sources: [first], format: .tar, name: "../Bad", in: root); fatalError("unsafe name accepted") } catch { }
        print("PASS: duplicate roots and unsafe output names rejected")
        let large = root.appendingPathComponent("Many")
        try FileManager.default.createDirectory(at: large, withIntermediateDirectories: true)
        for index in 0..<1500 { try Data("file \(index)".utf8).write(to: large.appendingPathComponent("file-\(index).txt")) }
        let many = try PackingInput.snapshot(large, name: "Many", coordinated: false)
        defer { try? FileManager.default.removeItem(at: many.snapshotDirectory) }
        let batch = try ArchivePacker.create(sources: [many], format: .zip, name: "Batch", in: root)
        let manyArchive = try ArchiveContainer.open(url: batch)
        precondition(manyArchive.entries.count == 1501)
        print("PASS: 1500-file ZIP batch")
        let cancel = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ArchivePacker.create(sources: [many], format: .tar, name: "Cancel", in: root)
        }
        do { _ = try await cancel.value; fatalError("cancellation ignored") } catch is CancellationError { }
        let beforeCancel = Set(try FileManager.default.contentsOfDirectory(atPath: root.path))
        let midCancel = Task.detached {
            try ArchivePacker.create(sources: [many], format: .zip, name: "MidCancel", in: root) { _, _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        do { _ = try await midCancel.value; fatalError("mid-task cancellation ignored") } catch is CancellationError { }
        let afterCancel = Set(try FileManager.default.contentsOfDirectory(atPath: root.path))
        precondition(beforeCancel == afterCancel, "packing cancellation rollback")
        let changed = many.items.first { !$0.isDirectory }!
        try Data("changed private snapshot with a different length".utf8).write(to: changed.url)
        do { _ = try ArchivePacker.create(sources: [many], format: .tar, name: "Changed", in: root); fatalError("changed snapshot accepted") } catch { }
        let afterFailure = Set(try FileManager.default.contentsOfDirectory(atPath: root.path))
        precondition(beforeCancel == afterFailure, "packing failure rollback")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
        do { _ = try PackingInput.snapshot(link, name: "link", coordinated: false); fatalError("symlink accepted") } catch { }
        print("PASS: cancellation and symbolic-link rejection")
        print("PASS: mid-task packing cancellation and changed-snapshot rollback")

        let fixtures = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("work/rar-fixtures")
        for version in [4, 5] {
            for suffix in ["encrypted", "encrypted_filenames", "solid_encrypted", "solid_encrypted_filenames"] {
                let url = fixtures.appendingPathComponent("test_read_format_rar\(version)_\(suffix).rar")
                let hidden = suffix.contains("filenames")
                if hidden {
                    do { _ = try RARArchive.open(url: url); fatalError("password not required") }
                    catch RARFailure.passwordRequired { }
                }
                let archive = try RARArchive.open(url: url, password: hidden ? "password" : nil)
                precondition(archive.entries.count == 4)
                let b = archive.entries.first { $0.path == "b.txt" }!
                let preview = try archive.previewText(b, password: "password")
                precondition(preview == "This is from b.txt")
                let output = try archive.extract(paths: ["b.txt"], outputRoot: root, password: "password")
                let extracted = try Data(contentsOf: output.appendingPathComponent("b.txt"))
                precondition(extracted == Data("This is from b.txt".utf8))
                let before = try FileManager.default.contentsOfDirectory(atPath: root.path)
                do { _ = try archive.extract(paths: ["b.txt"], outputRoot: root, password: "wrong"); fatalError("bad password accepted") } catch { }
                let after = try FileManager.default.contentsOfDirectory(atPath: root.path)
                precondition(Set(before) == Set(after), "bad-password rollback")
                if !hidden && !suffix.contains("solid") {
                    let d = archive.entries.first { $0.path == "d.txt" }!
                    let dText = try archive.previewText(d, password: "password2")
                    precondition(dText == "This is from d.txt")
                }
                precondition(archivedesk_codec_live_bytes() == 0, "native bounded allocation leak")
                print("PASS: RAR\(version) \(suffix), password preview/extraction and wrong-password rollback")
            }
        }
        let cancelledRAR = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try RARArchive.open(url: fixtures.appendingPathComponent("test_read_format_rar5_encrypted.rar"))
        }
        do { _ = try await cancelledRAR.value; fatalError("RAR cancellation ignored") } catch is CancellationError { }
        print("PASS: cancelled RAR initializer cleanup")
    }
}
