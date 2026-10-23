import Foundation
import CArchive

private extension Data {
    mutating func le16(_ value: UInt16) { append(UInt8(truncatingIfNeeded: value)); append(UInt8(value >> 8)) }
    mutating func le32(_ value: UInt32) { le16(UInt16(truncatingIfNeeded: value)); le16(UInt16(value >> 16)) }
}

@main @MainActor enum EncodingVerification {
    static var checks = 0
    static func check(_ value: Bool, _ label: String) {
        precondition(value, label); checks += 1
    }
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveDesk-Encoding-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let pairs: [(ArchiveEncoding, String)] = [(.gb18030, "中文文件目录说明书"), (.gbk, "中文文件目录说明书"),
            (.shiftJIS, "日本語のテキストです"), (.big5, "繁體中文檔案資料"), (.korean, "한국어 텍스트 미리보기"),
            (.cp437, "éotes.txt"), (.cp850, "éöü"), (.western, "Café naïve"), (.cp866, "Привет"), (.cyrillic, "Привет"),
            (.utf8, "中文🙂"), (.utf16LE, "中文🙂"), (.utf16BE, "中文🙂")]
        for (encoding, text) in pairs {
            let raw = ArchiveEncoding.convert(Data(text.utf8), from: "UTF-8", to: encoding.rawValue)!
            check(ArchiveTextPreview.decode(raw, encoding: encoding) == text, "Manual \(encoding)")
        }
        check(ArchiveTextPreview.decode(Data([0xd6, 0xd0, 0xce, 0xc4, 0xb2, 0xe2, 0xca, 0xd4, 10])) == "中文测试\n", "Auto GBK body")
        check(ArchiveTextPreview.decode(Data([0xc0, 0x80])) == nil, "Short malformed Unicode not guessed")
        check(ArchiveTextPreview.decode(Data([0xff, 0xfe, 0])) == nil, "Malformed BOM not legacy guessed")
        check(ArchiveTextPreview.decode(Data([0, 65]), encoding: .western) == nil, "Binary NUL rejected")
        check(ArchiveTextPreview.decode(Data([65, 1]), encoding: .western) == nil, "Binary control rejected")
        check(ArchiveTextPreview.decode(Data(repeating: 65, count: 256 * 1024 + 1)) == nil, "Text cap")
        check(ArchiveTextPreview.decode(Data([67, 97, 102, 0xe9])) == nil, "Ambiguous short text needs manual encoding")
        check(ArchiveTextPreview.decode(Data([67, 97, 102, 0xe9]), encoding: .western) == "Café", "Manual recovery")
        let fullSizeGBK = Data((0..<(128 * 1024)).flatMap { _ in [UInt8(0xd6), UInt8(0xd0)] })
        check(ArchiveTextPreview.decode(fullSizeGBK, encoding: .gbk)?.count == 128 * 1024, "Full text cap permits UTF8 expansion during round trip")
        let rawName = Data([0xb2, 0xbb, 0xb6, 0xc1, 0xce, 0xd2, 0xcb, 0xa2, 0xb3, 0xc9, 0xd7, 0xa9]) + Data(".txt".utf8)
        let body = Data([0xd6, 0xd0, 0xce, 0xc4, 0xb2, 0xe2, 0xca, 0xd4, 10])
        let url = root.appendingPathComponent("legacy.zip")
        try DebugArchiveFixture.encodedBytes([(rawName, body)]).write(to: url)
        let archive = try ZIPArchive.open(url: url)
        check(archive.entries[0].path == "不读我刷成砖.txt", "Auto legacy ZIP name")
        check(try archive.previewText(archive.entries[0]) == "中文测试\n", "Legacy ZIP body")
        let manual = try ZIPArchive.open(url: url, filenameEncoding: .gbk)
        check(manual.entries[0].path == archive.entries[0].path, "Manual filename override")
        let cp437 = try ZIPArchive.open(url: url, filenameEncoding: .cp437)
        check(cp437.entries[0].path != archive.entries[0].path, "Independent filename decoder")
        let output = try archive.extract(outputRoot: root.appendingPathComponent("out"))
        check(try Data(contentsOf: output.appendingPathComponent(archive.entries[0].path)) == body, "Extract exact original bytes")
        // ZIP flags are authoritative even with a manual legacy override.
        try DebugArchiveFixture.bytes([("日本語.txt", Data("UTF8".utf8))]).write(to: url)
        check(try ZIPArchive.open(url: url, filenameEncoding: .gbk).entries[0].path == "日本語.txt", "UTF8 flag wins")

        func unicodeExtra(_ path: String, validCRC: Bool = true) -> Data {
            var field = Data([1])
            field.le32(CRC32.checksum(rawName) ^ (validCRC ? 0 : 1)); field.append(Data(path.utf8))
            var extra = Data(); extra.le16(0x7075); extra.le16(UInt16(field.count)); extra.append(field)
            return extra
        }
        let unicodeURL = root.appendingPathComponent("unicode.zip")
        try DebugArchiveFixture.encodedBytes([(rawName, body)], deflated: true, extra: unicodeExtra("正确名称.txt")).write(to: unicodeURL)
        let unicodeZIP = try ZIPArchive.open(url: unicodeURL, filenameEncoding: .cp437)
        check(unicodeZIP.entries[0].path == "正确名称.txt", "CRC verified Unicode extra wins manual charset")
        check(try unicodeZIP.previewText(unicodeZIP.entries[0]) == "中文测试\n", "Unicode extra Deflate preview locates raw payload")
        let unicodeOutput = try unicodeZIP.extract(outputRoot: root.appendingPathComponent("unicode"))
        check(try Data(contentsOf: unicodeOutput.appendingPathComponent("正确名称.txt")) == body, "Unicode extra output consistent")
        try DebugArchiveFixture.encodedBytes([(rawName, body)], extra: unicodeExtra("错误名称.txt", validCRC: false)).write(to: unicodeURL)
        check(try ZIPArchive.open(url: unicodeURL).entries[0].path == "不读我刷成砖.txt", "Bad Unicode-extra CRC ignored")
        try DebugArchiveFixture.encodedBytes([(rawName, body)], extra: unicodeExtra("../escape.txt")).write(to: unicodeURL)
        do { _ = try ZIPArchive.open(url: unicodeURL); preconditionFailure("Unicode path traversal accepted") } catch { checks += 1 }

        for size in [0, 1, 256 * 1024, 256 * 1024 + 1, 2 * 1024 * 1024] {
            var seed: UInt64 = 71
            let payload = Data((0..<size).map { _ in
                seed = seed &* 6364136223846793005 &+ 1
                return UInt8(truncatingIfNeeded: seed >> 32)
            })
            let zipped = root.appendingPathComponent("chunks-\(size).zip")
            try DebugArchiveFixture.encodedBytes([(Data("data.bin".utf8), payload)], deflated: true).write(to: zipped)
            let chunks = try ZIPArchive.open(url: zipped)
            let destination = try chunks.extract(outputRoot: root.appendingPathComponent("chunks-\(size)"))
            check(try Data(contentsOf: destination.appendingPathComponent("data.bin")) == payload, "Deflate I/O boundary \(size)")
        }

        let model = WorkspaceModel()
        let modelFolder = root.appendingPathComponent("model-first")
        try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: false)
        let modelURL = modelFolder.appendingPathComponent("archive.zip")
        try Data(contentsOf: url).write(to: modelURL)
        model.importArchive(modelURL, alreadyPrivate: true)
        while model.isBusy { try await Task.sleep(for: .milliseconds(20)) }
        model.select("日本語.txt")
        for _ in 0..<100 where !model.hasTextPreviewBytes { try await Task.sleep(for: .milliseconds(20)) }
        check(model.hasTextPreviewBytes, "Workspace verified bytes available")
        model.changeTextEncoding(.gbk)
        check(model.previewText == "UTF8", "Workspace encoding switch")
        model.handleMemoryPressure()
        check(!model.hasTextPreviewBytes && model.previewText == nil && model.textEncoding == .auto, "Memory warning releases raw text")
        let westernFolder = root.appendingPathComponent("model-second")
        try FileManager.default.createDirectory(at: westernFolder, withIntermediateDirectories: false)
        let westernURL = westernFolder.appendingPathComponent("western.zip")
        try DebugArchiveFixture.bytes([("Western.txt", Data([67, 97, 102, 0xe9]))]).write(to: westernURL)
        model.importArchive(westernURL, alreadyPrivate: true)
        while model.isBusy { try await Task.sleep(for: .milliseconds(20)) }
        model.select("Western.txt")
        for _ in 0..<100 where !model.hasTextPreviewBytes { try await Task.sleep(for: .milliseconds(20)) }
        check(model.hasTextPreviewBytes && model.previewText == nil, "Undecodable text keeps bounded retry bytes")
        model.changeTextEncoding(.western)
        for _ in 0..<100 where model.previewText == nil { try await Task.sleep(for: .milliseconds(20)) }
        check(model.previewText == "Café", "Async manual text recovery")
        model.goUp()
        check(!model.hasTextPreviewBytes && model.previewText == nil, "Navigation clears decoded and raw text")
        let reindexFolder = root.appendingPathComponent("model-reindex")
        try FileManager.default.createDirectory(at: reindexFolder, withIntermediateDirectories: false)
        let reindexURL = reindexFolder.appendingPathComponent("legacy.zip")
        try DebugArchiveFixture.encodedBytes([(rawName, body)]).write(to: reindexURL)
        model.importArchive(reindexURL, alreadyPrivate: true)
        while model.isBusy { try await Task.sleep(for: .milliseconds(20)) }
        model.changeZIPEncoding(.utf8)
        while model.isBusy { try await Task.sleep(for: .milliseconds(20)) }
        check(model.errorMessage != nil && FileManager.default.fileExists(atPath: reindexURL.path), "Failed charset reindex preserves current snapshot")
        check(model.archive?.entries[0].path == "不读我刷成砖.txt", "Failed reindex preserves old index")
        model.errorMessage = nil
        model.changeZIPEncoding(.gbk)
        while model.isBusy { try await Task.sleep(for: .milliseconds(20)) }
        check(model.zipFilenameEncoding == .gbk && model.errorMessage == nil, "Successful charset reindex without another import copy")
        let encryptedURL = root.appendingPathComponent("encrypted.zip")
        try DebugArchiveFixture.encodedBytes([(rawName, body)], flags: 1).write(to: encryptedURL)
        let encrypted = try ArchiveContainer.open(url: encryptedURL)
        check(encrypted.requiresPassword(encrypted.entries[0]), "Visible encrypted legacy filename still requires password")
        check(try encrypted.previewTextBytes(encrypted.entries[0]) == nil, "Unsupported encrypted ZIP cannot expose plaintext retry bytes")

        // Optional user-supplied reproduction. Never commit this private archive.
        if CommandLine.arguments.count > 1 {
            let source = URL(fileURLWithPath: CommandLine.arguments[1])
            let actual = try ZIPArchive.open(url: source)
            check(actual.entries.count == 9, "Original nine entries")
            for name in ["不读我刷成砖.txt", "ZY1280最新说明书-V350.pdf", "核实硬件版本再刷对应固件.jpg"] {
                check(actual.entries.contains { $0.path == name }, "Original filename \(name)")
            }
            let note = actual.entries.first { $0.path == "不读我刷成砖.txt" }!
            let data = try actual.previewTextBytes(note)!
            check(data.count == 3985, "Original TXT verified byte count")
            check(ArchiveTextPreview.decode(data)?.contains("刷") == true, "Original GBK text readable")
            check(ArchiveTextPreview.decode(data, encoding: .utf8) == nil, "Original forced UTF8 rejects")
            check(ArchiveTextPreview.decode(data, encoding: .gbk) != nil, "Original manual GBK recovers")
            let extracted = try actual.extract(outputRoot: root.appendingPathComponent("original"))
            for entry in actual.entries where !entry.isDirectory {
                let payload = try Data(contentsOf: extracted.appendingPathComponent(entry.path))
                check(payload.count == entry.uncompressedSize && CRC32.checksum(payload) == entry.crc32, "Original output name/size/CRC")
            }
        }
        check(archivedesk_codec_live_bytes() == 0, "Decoder allocations released")
        print("PASS: \(checks) encoding, preview, original ZIP and cache checks")
    }
}
