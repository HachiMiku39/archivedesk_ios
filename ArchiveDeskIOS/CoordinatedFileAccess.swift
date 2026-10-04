import Foundation

enum CoordinatedFileAccess {
    static func snapshot(of externalURL: URL) throws -> URL {
            let scoped = externalURL.startAccessingSecurityScopedResource()
            defer { if scoped { externalURL.stopAccessingSecurityScopedResource() } }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveDesk-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var succeeded = false
            defer { if !succeeded { try? FileManager.default.removeItem(at: directory) } }
            let target = directory.appendingPathComponent(externalURL.lastPathComponent)
            var coordinationError: NSError?
            var operationError: Error?
            NSFileCoordinator().coordinate(readingItemAt: externalURL, options: [.withoutChanges], error: &coordinationError) { readableURL in
                do {
                    let values = try readableURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ArchiveFailure.unsafePath(readableURL.lastPathComponent) }
                    let input = try FileHandle(forReadingFrom: readableURL)
                    defer { try? input.close() }
                    guard FileManager.default.createFile(atPath: target.path, contents: nil) else { throw ArchiveFailure.capacity }
                    let output = try FileHandle(forWritingTo: target)
                    defer { try? output.close() }
                    while true {
                        try Task.checkCancellation()
                        let bytes = try input.read(upToCount: 256 * 1_024) ?? Data()
                        if bytes.isEmpty { break }
                        try output.write(contentsOf: bytes)
                    }
                    try output.synchronize()
                }
                catch { operationError = error }
            }
            if let coordinationError { throw coordinationError }
            if let operationError { throw operationError }
            try Task.checkCancellation()
            succeeded = true
            return target
    }
}
