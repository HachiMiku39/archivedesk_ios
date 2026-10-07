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
    var passwordDecodable: Bool = false
    var isDirectory: Bool { path.hasSuffix("/") }
    var isEncrypted: Bool { flags & 0x41 != 0 }
    var isExtractable: Bool { (!isEncrypted || passwordDecodable) && !isLink && (isDirectory || compressionMethod == 0 || compressionMethod == 8 || nativeFormat != nil) }
    var methodName: String {
        if nativeFormat != nil { return String(localized: "Native format decoder") }
        if compressionMethod == 0 { return String(localized: "Stored") }
        if compressionMethod == 8 { return "Deflate" }
        return String(localized: "Not yet supported")
    }
}

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case files, packing, tasks, information
    var id: Self { self }
    var title: String {
        switch self {
        case .files: return String(localized: "Files")
        case .packing: return String(localized: "Create archive")
        case .tasks: return String(localized: "Tasks")
        case .information: return String(localized: "Information")
        }
    }
    var symbol: String {
        switch self { case .files: "archivebox"; case .packing: "archivebox.fill"; case .tasks: "list.bullet.rectangle"; case .information: "info.circle" }
    }
}

enum CollisionPolicy: Sendable { case skip, replace, keepBoth }

/// Capture the user's extraction scope before presenting a destination/password.
/// Folder matching is component-boundary aware and includes empty directories.
enum ArchiveExtractionScope: Equatable, Sendable {
    case entry(String), folder(String), items(Set<String>), all
    func entries(in archive: [ArchiveEntry]) -> [ArchiveEntry] {
        switch self {
        case .entry(let path): return archive.filter { $0.path == path }
        case .folder(let path):
            let prefix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
            return archive.filter { $0.path.hasPrefix(prefix) }
        case .items(let paths):
            return archive.filter { entry in
                var candidate = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if paths.contains(entry.path) || paths.contains(candidate) { return true }
                while !candidate.isEmpty {
                    candidate = (candidate as NSString).deletingLastPathComponent
                    if paths.contains(candidate) || paths.contains(candidate + "/") { return true }
                }
                return false
            }
        case .all: return archive
        }
    }
}

enum ArchivePreviewKind: Sendable {
    case text, image, audio, video
    static func forPath(_ path: String) -> Self? {
        switch (path as NSString).pathExtension.lowercased() {
        case "txt", "md", "json", "xml", "csv", "log", "swift", "plist", "yaml", "yml": .text
        case "jpg", "jpeg", "png", "webp": .image
        case "flac", "mp3", "m4a", "aac", "wav", "ogg", "opus": .audio
        case "mp4", "mov", "mkv", "webm": .video
        default: nil
        }
    }
}

/// Unicode decoding uses Swift's open-source standard-library codecs. No
/// heuristic legacy-codepage guesses or unbounded document loading.
enum ArchiveTextPreview {
    static func decode(_ data: Data) -> String? {
        guard data.count <= 256 * 1024 else { return nil }
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) {
            guard data.count % 2 == 0 else { return nil }
            let little = data.first == 0xff
            let bytes = Array(data.dropFirst(2))
            let units = stride(from: 0, to: bytes.count, by: 2).map { i in
                little ? UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8 : UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1])
            }
            let text = String(decoding: units, as: UTF16.self)
            return Array(text.utf16) == units ? text : nil
        }
        let bytes = data.starts(with: [0xef, 0xbb, 0xbf]) ? data.dropFirst(3) : data[...]
        let text = String(decoding: bytes, as: UTF8.self)
        return text.utf8.elementsEqual(bytes) ? text : nil
    }
}

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
        guard let rows = try? folderItems(entries: entries, folder: navigation.folder) else { return [] }
        return (try? search(rows, query: navigation.search)) ?? []
    }
    static func folderItems(entries: [ArchiveEntry], folder: String) throws -> [BrowserItem] {
        let prefix = folder.isEmpty ? "" : folder + "/"
        var items: [String: BrowserItem] = [:]
        for entry in entries {
            try Task.checkCancellation()
            guard entry.path.hasPrefix(prefix) else { continue }
            let suffix = entry.path.dropFirst(prefix.count)
            guard !suffix.isEmpty, let name = suffix.split(separator: "/").first else { continue }
            let directory = suffix.contains("/")
            let path = prefix + name
            items[path] = BrowserItem(path: path, name: String(name), isDirectory: directory, entry: directory ? nil : entry)
        }
        let sorted = items.values.sorted { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        try Task.checkCancellation()
        return sorted
    }
    static func search(_ items: [BrowserItem], query: String) throws -> [BrowserItem] {
        try Task.checkCancellation()
        guard !query.isEmpty else { return items }
        return try items.filter {
            try Task.checkCancellation()
            return $0.name.localizedStandardContains(query)
        }
    }
}

enum ArchiveFailure: LocalizedError {
    case malformed(String), unsafePath(String), unsupported(String), capacity, memoryLimit, codecInitialization(String, Int32, UInt64), resourceLimit(String), storageSpace(UInt64, UInt64), crcMismatch(String), cancelled
    var errorDescription: String? {
        switch self {
        case .malformed(let message): message
        case .unsafePath(let path): "Unsafe archive path: \(path)"
        case .unsupported(let message): message
        case .capacity: String(localized: "The operation exceeded an application resource limit. This does not mean the disk is full.")
        case .memoryLimit: String(localized: "The decoder could not allocate memory within the app's safety budget. Free disk space cannot resolve this memory limit.")
        case .codecInitialization(let step, let code, let live): String(localized: "Archive engine initialization failed.") + "\n" + step + "; errno=" + String(code) + (code != 0 ? " (" + NSError(domain: NSPOSIXErrorDomain, code: Int(code)).localizedDescription + ")" : "") + "; " + String(localized: "Codec memory in use:") + " " + live.formatted(.byteCount(style: .memory))
        case .resourceLimit(let detail): String(localized: "Application safety limit exceeded:") + " " + detail
        case .storageSpace(let needed, let available): String(localized: "Not enough space on the destination volume.") + " " + String(localized: "Required:") + " " + needed.formatted(.byteCount(style: .file)) + "; " + String(localized: "Available:") + " " + available.formatted(.byteCount(style: .file))
        case .crcMismatch(let path): "CRC verification failed for \(path)."
        case .cancelled: "The operation was cancelled."
        }
    }
}
