import Foundation

@main
@MainActor
enum CoreVerification {
    static var checks = 0
    static func check(_ condition: Bool, _ message: String) {
        precondition(condition, message); checks += 1
    }
    static func rejects(_ message: String, _ body: () throws -> Void) {
        do { try body(); fatalError("Accepted: \(message)") } catch { checks += 1 }
    }

    @MainActor static func main() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveDesk-Tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        func open(_ data: Data, name: String = UUID().uuidString) throws -> ZIPArchive {
            let url = temporary.appendingPathComponent(name + ".zip")
            try data.write(to: url)
            return try ZIPArchive.open(url: url)
        }
        let root = temporary.appendingPathComponent("outputs")

        check(CRC32.checksum(Data("123456789".utf8)) == 0xcbf43926, "CRC standard vector")
        let first = Data("1234".utf8).withUnsafeBytes { CRC32.update(bytes: $0) }
        check(Data("56789".utf8).withUnsafeBytes { CRC32.update(first, bytes: $0) } == 0xcbf43926, "Incremental CRC")
        for path in ["../escape", "/absolute", "A//B", "\\escape", "a/./b", "a\0b", "C:/escape", "/", "a/../b"] {
            rejects(path) { _ = try ArchiveSafety.safeRelativePath(path) }
        }

        let text = Data("ArchiveDesk\n".utf8)
        let fixture = DebugArchiveFixture.bytes([("Folder/Readme.txt", text), ("Folder/日本語.txt", Data("日本語".utf8)), ("empty.bin", Data())])
        let archive = try open(fixture)
        check(archive.entries.count == 3, "Index count")
        check(try archive.previewText(archive.entries[0]) == "ArchiveDesk\n", "Verified preview")
        let output = try archive.extract(outputRoot: root)
        check(try Data(contentsOf: output.appendingPathComponent("Folder/Readme.txt")) == text, "Preserved filename case")
        check(FileManager.default.fileExists(atPath: output.appendingPathComponent("empty.bin").path), "Zero byte output")

        check(try DestinationPolicy.classify(inAppDocuments: true, isUbiquitous: false, volumeIsLocal: true, volumeIsInternal: true) == .appDocuments, "App Documents writable")
        check(try DestinationPolicy.classify(inAppDocuments: false, isUbiquitous: true, volumeIsLocal: true, volumeIsInternal: true) == .iCloud, "System iCloud writable")
        check(try DestinationPolicy.classify(inAppDocuments: false, isUbiquitous: false, volumeIsLocal: true, volumeIsInternal: false) == .externalVolume, "External local volume writable")
        rejects("Provider cache is not proof of local storage") {
            _ = try DestinationPolicy.classify(inAppDocuments: false, isUbiquitous: false, volumeIsLocal: true, volumeIsInternal: true)
        }
        rejects("Unknown provider stays read-only") {
            _ = try DestinationPolicy.classify(inAppDocuments: false, isUbiquitous: nil, volumeIsLocal: nil, volumeIsInternal: nil)
        }
        rejects("Network cloud volume stays read-only") {
            _ = try DestinationPolicy.classify(inAppDocuments: false, isUbiquitous: false, volumeIsLocal: false, volumeIsInternal: false)
        }
        let missingRoot = temporary.appendingPathComponent("do-not-create")
        rejects("Missing external root is never recreated") { _ = try archive.extract(outputRoot: missingRoot, createOutputRoot: false) }
        check(!FileManager.default.fileExists(atPath: missingRoot.path), "No external ancestor creation")
        let existing = root.appendingPathComponent("keep.txt")
        try text.write(to: existing)
        _ = try archive.extract(paths: ["Folder/Readme.txt"], outputRoot: root, createOutputRoot: false)
        check(try Data(contentsOf: existing) == text, "Existing destination content preserved")
        let symlinkRoot = temporary.appendingPathComponent("root-link")
        try FileManager.default.createSymbolicLink(at: symlinkRoot, withDestinationURL: root)
        rejects("Output root symlink") { _ = try archive.extract(outputRoot: symlinkRoot, createOutputRoot: false) }

        // On macOS the harness workspace is inside Documents. On iOS the app's
        // Documents root is sandbox-specific; production never grants all Documents.
        let coordinatedRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("work/Coordinated-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: coordinatedRoot) }
        do {
            try FileManager.default.createDirectory(at: coordinatedRoot, withIntermediateDirectories: true)
            let coordinated = try CoordinatedFileAccess.extract(archive, paths: ["Folder/Readme.txt"], to: coordinatedRoot)
            check(coordinated.destination == .appDocuments, "Coordinated granted-directory result")
            check(try Data(contentsOf: coordinated.directory.appendingPathComponent("Folder/Readme.txt")) == text, "Coordinated output bytes verified")
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteUnknownError {
            // The desktop workspace is iCloud-backed; this sandbox cannot perform
            // its coordinated writes. This is a reported skip, never a passed check.
            print("SKIP: desktop coordinated-write integration (Cocoa 512); verify with the iOS system picker UI test")
        }
        do {
            let snapshot = try CoordinatedFileAccess.snapshot(of: archive.url)
            defer { try? FileManager.default.removeItem(at: snapshot.deletingLastPathComponent()) }
            check(try Data(contentsOf: snapshot) == fixture, "External read snapshot preserves source")
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadUnknownError {
            print("SKIP: desktop coordinated-read integration (Cocoa 256); native iOS verification required")
        }

        let rootItems = ArchiveBrowser.items(entries: archive.entries, navigation: ArchiveNavigation())
        check(rootItems.map(\.name) == ["Folder", "empty.bin"], "Implicit folder browsing")
        var navigation = ArchiveNavigation()
        navigation.enter("Folder")
        check(ArchiveBrowser.items(entries: archive.entries, navigation: navigation).count == 2, "Nested browsing")
        navigation.selection = "Folder/Readme.txt"
        navigation.goUp()
        check(navigation.folder.isEmpty && navigation.selection == nil, "Parent routing")

        rejects("Case alias at parent") {
            _ = try open(DebugArchiveFixture.bytes([("A/x", text), ("a/y", text)]))
        }
        rejects("Unicode alias") {
            _ = try open(DebugArchiveFixture.bytes([("é.txt", text), ("e\u{301}.txt", text)]))
        }
        rejects("File-directory conflict") {
            _ = try open(DebugArchiveFixture.bytes([("A", text), ("A/file", text)]))
        }
        rejects("Traversal archive") { _ = try open(DebugArchiveFixture.bytes([("../outside", text)])) }
        rejects("Truncated archive") { _ = try open(fixture.dropLast(12)) }

        var badCRC = DebugArchiveFixture.bytes([("bad.txt", text)])
        badCRC[30 + "bad.txt".utf8.count] ^= 0xff
        let damaged = try open(badCRC)
        rejects("CRC corruption") { _ = try damaged.extract(outputRoot: temporary.appendingPathComponent("corruption")) }
        check(try FileManager.default.contentsOfDirectory(atPath: temporary.appendingPathComponent("corruption").path).isEmpty, "Failure cleans staging")

        var link = DebugArchiveFixture.bytes([("link.txt", text)])
        let central = 30 + "link.txt".utf8.count + text.count
        link.set32(central + 38, 0xa1ff0000)
        rejects("Unix symlink") { _ = try open(link) }

        var encrypted = DebugArchiveFixture.bytes([("secret.txt", text)])
        let secretCentral = 30 + "secret.txt".utf8.count + text.count
        encrypted.set16(6, 0x801); encrypted.set16(secretCentral + 8, 0x801)
        let secret = try open(encrypted)
        check(secret.entries[0].isEncrypted && !secret.entries[0].isExtractable, "Encrypted capability reporting")
        rejects("Encrypted stored extraction") { _ = try secret.extract(outputRoot: root) }

        var mismatchedName = DebugArchiveFixture.bytes([("name.txt", text)])
        mismatchedName[30] = UInt8(ascii: "N")
        let mismatched = try open(mismatchedName)
        rejects("Local central name mismatch") { _ = try mismatched.extract(outputRoot: root) }

        var legacy = DebugArchiveFixture.bytes([("e.txt", text)])
        let legacyCentral = 30 + "e.txt".utf8.count + text.count
        legacy.set16(6, 0); legacy.set16(legacyCentral + 8, 0)
        legacy[30] = 0x82; legacy[legacyCentral + 46] = 0x82
        let legacyZIP = try open(legacy)
        check(legacyZIP.entries[0].path == "é.txt", "ZIP CP437 filename")
        _ = try legacyZIP.extract(outputRoot: root)
        checks += 1

        var deflated = DebugArchiveFixture.bytes([("deflate.txt", text)])
        let deflateCentral = 30 + "deflate.txt".utf8.count + text.count
        deflated.set16(8, 8); deflated.set16(deflateCentral + 10, 8)
        let indexedDeflate = try open(deflated)
        check(indexedDeflate.entries[0].isExtractable, "Deflate decoder advertised")
        rejects("Stored bytes mislabeled as Deflate") { _ = try indexedDeflate.extract(outputRoot: root) }

        // Convert a tiny archive to a ZIP64 EOCD/locator fixture; no huge RAM allocation.
        var wide = DebugArchiveFixture.bytes([("wide.txt", text)])
        let oldEnd = wide.count - 22
        let directory = UInt64(30 + "wide.txt".utf8.count + text.count)
        let directorySize = UInt64(oldEnd) - directory
        let oldEOCD = wide.suffix(22)
        wide.removeLast(22)
        wide.le32(0x06064b50); wide.le64(44); wide.le16(45); wide.le16(45); wide.le32(0); wide.le32(0)
        wide.le64(1); wide.le64(1); wide.le64(directorySize); wide.le64(directory)
        wide.le32(0x07064b50); wide.le32(0); wide.le64(UInt64(oldEnd)); wide.le32(1)
        let newEnd = wide.count
        wide.append(oldEOCD)
        wide.set16(newEnd + 8, 0xffff); wide.set16(newEnd + 10, 0xffff)
        wide.set32(newEnd + 12, 0xffffffff); wide.set32(newEnd + 16, 0xffffffff)
        let zip64 = try open(wide)
        check(zip64.entries.count == 1, "ZIP64 end record")
        _ = try zip64.extract(outputRoot: root)
        checks += 1

        var perEntryWide = DebugArchiveFixture.bytes([("entry64.txt", text)])
        let wideCentral = 30 + "entry64.txt".utf8.count + text.count
        let wideExtraOffset = wideCentral + 46 + "entry64.txt".utf8.count
        var wideExtra = Data()
        wideExtra.le16(1); wideExtra.le16(24); wideExtra.le64(UInt64(text.count)); wideExtra.le64(UInt64(text.count)); wideExtra.le64(0)
        perEntryWide.insert(contentsOf: wideExtra, at: wideExtraOffset)
        perEntryWide.set32(wideCentral + 20, 0xffffffff); perEntryWide.set32(wideCentral + 24, 0xffffffff)
        perEntryWide.set32(wideCentral + 42, 0xffffffff); perEntryWide.set16(wideCentral + 30, UInt16(wideExtra.count))
        perEntryWide.set32(perEntryWide.count - 22 + 12, UInt32(46 + "entry64.txt".utf8.count + wideExtra.count))
        let entry64 = try open(perEntryWide)
        check(entry64.entries[0].uncompressedSize == UInt64(text.count), "ZIP64 entry values")
        _ = try entry64.extract(outputRoot: root)
        checks += 1

        // A 3 MiB stored file exercises multiple bounded read/write/CRC iterations.
        let large = Data(repeating: 0x6a, count: 3 * 1_024 * 1_024)
        let streaming = try open(DebugArchiveFixture.bytes([("large.bin", large)]))
        let largeOutput = try streaming.extract(outputRoot: root)
        check(try Data(contentsOf: largeOutput.appendingPathComponent("large.bin")) == large, "Streaming multi-chunk extraction")
        let cancelledRoot = temporary.appendingPathComponent("cancelled")
        let cancelled = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try streaming.extract(outputRoot: cancelledRoot)
        }
        do { _ = try await cancelled.value; fatalError("Cancellation ignored") } catch is CancellationError { checks += 1 }
        check((try? FileManager.default.contentsOfDirectory(atPath: cancelledRoot.path).isEmpty) != false, "Cancelled staging removed")

        // Resizing and hinge diagnostics cannot mutate domain navigation or preview.
        let model = WorkspaceModel()
        model.importArchive(archive.url, alreadyPrivate: true)
        for _ in 0..<400 where model.isBusy { try await Task.sleep(for: .milliseconds(5)) }
        check(model.archive != nil && !model.isBusy, "Workspace import completes")
        model.enterFolder("Folder"); model.select("Folder/Readme.txt")
        for _ in 0..<400 where model.previewText == nil { try await Task.sleep(for: .milliseconds(5)) }
        let retained = model.navigation
        for dimensions in [(382.0, 644.0), (669, 951), (951, 669), (400, 700)] {
            model.diagnostics = LayoutDiagnostics(width: dimensions.0, height: dimensions.1, divisionCount: 1)
            model.hingeStatus = "Partially open"
            check(model.navigation == retained && model.previewText == "ArchiveDesk\n", "Layout keeps selection and preview")
        }
        print("PASS: \(checks) archive, streaming, cancellation, Unicode, ZIP64 and workspace checks")
    }
}

private extension Data {
    mutating func le16(_ value: UInt16) { append(UInt8(value & 0xff)); append(UInt8(value >> 8)) }
    mutating func le32(_ value: UInt32) { le16(UInt16(value & 0xffff)); le16(UInt16(value >> 16)) }
    mutating func le64(_ value: UInt64) { le32(UInt32(value & 0xffffffff)); le32(UInt32(value >> 32)) }
    mutating func set16(_ offset: Int, _ value: UInt16) { self[offset] = UInt8(value & 0xff); self[offset + 1] = UInt8(value >> 8) }
    mutating func set32(_ offset: Int, _ value: UInt32) { set16(offset, UInt16(value & 0xffff)); set16(offset + 2, UInt16(value >> 16)) }
}
