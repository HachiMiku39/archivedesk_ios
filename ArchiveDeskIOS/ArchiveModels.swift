import Foundation

struct ArchiveEntry: Identifiable, Hashable, Sendable {
    let id: Int
    let path: String
    let compressedSize: UInt64
    let uncompressedSize: UInt64
    let crc32: UInt32
    let compressionMethod: UInt16
    let localHeaderOffset: UInt64
    var flags: UInt16 = 0
    var isLink: Bool = false
    var rawName: Data = Data()
    var nativeFormat: String? = nil
    var hasCRC: Bool = true
    var isDirectory: Bool { path.hasSuffix("/") }
    var isEncrypted: Bool { flags & 0x41 != 0 }
    var isExtractable: Bool { !isEncrypted && !isLink && (isDirectory || compressionMethod == 0 || compressionMethod == 8 || nativeFormat != nil) }
    var methodName: String {
        if nativeFormat != nil { return String(localized: "Native format decoder") }
        if compressionMethod == 0 { return String(localized: "Stored") }
        if compressionMethod == 8 { return "Deflate" }
        return String(localized: "Not yet supported")
    }
}

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case files, tasks, information
    var id: Self { self }
    var title: String {
        switch self {
        case .files: return String(localized: "Files")
        case .tasks: return String(localized: "Tasks")
        case .information: return String(localized: "Information")
        }
    }
    var symbol: String {
        switch self { case .files: "archivebox"; case .tasks: "list.bullet.rectangle"; case .information: "info.circle" }
    }
}

enum CollisionPolicy: Sendable { case skip, replace, keepBoth }

/// Navigation belongs to the workspace, not the presentation or device pose.
struct ArchiveNavigation: Equatable, Sendable {
    var folder = ""
    var selection: String?
    var search = ""

    mutating func enter(_ path: String) {
        folder = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        selection = nil
        search = ""
    }
    mutating func goUp() { enter((folder as NSString).deletingLastPathComponent) }
}

struct BrowserItem: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let name: String
    let isDirectory: Bool
    let entry: ArchiveEntry?
}

enum ArchiveBrowser {
    static func items(entries: [ArchiveEntry], navigation: ArchiveNavigation) -> [BrowserItem] {
        let prefix = navigation.folder.isEmpty ? "" : navigation.folder + "/"
        var items: [String: BrowserItem] = [:]
        for entry in entries where entry.path.hasPrefix(prefix) {
            let suffix = entry.path.dropFirst(prefix.count)
            guard !suffix.isEmpty, let name = suffix.split(separator: "/").first else { continue }
            let directory = suffix.contains("/")
            let path = prefix + name
            items[path] = BrowserItem(path: path, name: String(name), isDirectory: directory, entry: directory ? nil : entry)
        }
        return items.values.filter { navigation.search.isEmpty || $0.name.localizedStandardContains(navigation.search) }
            .sorted { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

enum ArchiveFailure: LocalizedError {
    case malformed(String), unsafePath(String), unsupported(String), capacity, crcMismatch(String), cancelled
    var errorDescription: String? {
        switch self {
        case .malformed(let message): message
        case .unsafePath(let path): "Unsafe archive path: \(path)"
        case .unsupported(let message): message
        case .capacity: "There is not enough available storage for this operation."
        case .crcMismatch(let path): "CRC verification failed for \(path)."
        case .cancelled: "The operation was cancelled."
        }
    }
}
