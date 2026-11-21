import Foundation
import Darwin

enum ExtractionConflictChoice: Sendable { case replace, replaceAll, skip, cancel }

/// A background file operation waits here; the main actor remains free to show
/// the decision sheet. Cancellation is checked even when no button is pressed.
final class ExtractionConflictPrompt: Identifiable, @unchecked Sendable {
  let id = UUID()
  let path: String
  private let condition = NSCondition()
  private var choice: ExtractionConflictChoice?
  init(path: String) { self.path = path }
  func resolve(_ answer: ExtractionConflictChoice) {
    condition.lock(); defer { condition.unlock() }
    if choice == nil { choice = answer; condition.broadcast() }
  }
  func wait() throws -> ExtractionConflictChoice {
    condition.lock(); defer { condition.unlock() }
    while choice == nil {
      try Task.checkCancellation()
      _ = condition.wait(until: Date(timeIntervalSinceNow: 0.2))
    }
    try Task.checkCancellation()
    return choice!
  }
}

enum ExtractionPublication {
  static func checkDirectory(_ url: URL) throws {
    var path = ""
    for part in url.path.split(separator: "/") {
      guard part != ".", part != ".." else { throw DestinationFailure.invalidDirectory }
      path += "/" + part
      if path == "/var" || path == "/tmp" { path = "/private" + path }
      var info = stat()
      guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { throw DestinationFailure.invalidDirectory }
    }
  }
  static func inspect(_ url: URL) throws -> stat? {
    var info = stat()
    if lstat(url.path, &info) == 0 { return info }
    guard errno == ENOENT else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    return nil
  }

  /// Revalidate the file approved by the prompt, including the identity of the
  /// item actually moved. Both names stay on the selected destination volume.
  static func backUp(_ target: URL, matching old: stat) throws -> URL {
    func matches(_ current: stat) -> Bool {
      current.st_dev == old.st_dev && current.st_ino == old.st_ino &&
        current.st_mode == old.st_mode && (current.st_mode & S_IFMT) == S_IFREG &&
        current.st_nlink == 1 && current.st_size == old.st_size &&
        current.st_mtimespec.tv_sec == old.st_mtimespec.tv_sec &&
        current.st_mtimespec.tv_nsec == old.st_mtimespec.tv_nsec
    }
    guard let current = try inspect(target), matches(current),
          current.st_ctimespec.tv_sec == old.st_ctimespec.tv_sec,
          current.st_ctimespec.tv_nsec == old.st_ctimespec.tv_nsec else { throw DestinationFailure.changed }
    let saved = target.deletingLastPathComponent().appendingPathComponent("ArchiveDesk-backup-" + UUID().uuidString)
    let fm = FileManager.default
    try fm.moveItem(at: target, to: saved)
    do {
      guard let moved = try inspect(saved), matches(moved) else { throw DestinationFailure.changed }
    } catch {
      try? fm.moveItem(at: saved, to: target)
      throw error
    }
    return saved
  }
  /// Merge only decoded, verified output. All conflict decisions precede writes.
  /// Originals are moved beside their replacement, never deleted or recopied.
  static func merge(_ source: URL, into destination: URL,
                    conflict: (String) throws -> ExtractionConflictChoice) throws {
    try checkDirectory(source); try checkDirectory(destination)
    let fm = FileManager.default
    guard let walk = fm.enumerator(at: source, includingPropertiesForKeys: nil) else { throw DestinationFailure.invalidDirectory }
    var files: [URL] = []
    for case let file as URL in walk { try Task.checkCancellation(); files.append(file) }
    files.sort { $0.path < $1.path }
    var plan: [(file: URL, target: URL, old: stat?)] = []
    var replaceAll = false
    let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL.path
    for file in files {
      try Task.checkCancellation()
      let fullPath = file.resolvingSymlinksInPath().standardizedFileURL.path
      guard fullPath.hasPrefix(sourcePath + "/") else { throw ArchiveFailure.unsafePath(file.lastPathComponent) }
      let relative = String(fullPath.dropFirst(sourcePath.count + 1))
      let target = destination.appendingPathComponent(try ArchiveSafety.outputPath(relative))
      guard let incoming = try inspect(file), (incoming.st_mode & S_IFMT) == S_IFDIR ||
              ((incoming.st_mode & S_IFMT) == S_IFREG && incoming.st_nlink == 1) else { throw ArchiveFailure.unsafePath(relative) }
      var parent = target.deletingLastPathComponent()
      while parent.path.count >= destination.path.count {
        if try inspect(parent) != nil { try checkDirectory(parent); break }
        parent.deleteLastPathComponent()
      }
      let old = try inspect(target)
      if let old {
        guard (old.st_mode & S_IFMT) == (incoming.st_mode & S_IFMT),
              (old.st_mode & S_IFMT) == S_IFDIR || old.st_nlink == 1 else { throw ArchiveFailure.unsafePath(relative) }
        if (incoming.st_mode & S_IFMT) == S_IFREG {
          let answer = replaceAll ? ExtractionConflictChoice.replace : try conflict(relative)
          try Task.checkCancellation()
          switch answer {
          case .skip: continue
          case .cancel: throw CancellationError()
          case .replaceAll: replaceAll = true
          case .replace: break
          }
        }
      }
      plan.append((file, target, old))
    }
    try Task.checkCancellation()
    for item in plan {
      try Task.checkCancellation()
      try checkDirectory(item.target.deletingLastPathComponent())
      let incoming = try fm.attributesOfItem(atPath: item.file.path)
      if incoming[.type] as? FileAttributeType == .typeDirectory {
        if item.old == nil { try fm.createDirectory(at: item.target, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        else { try checkDirectory(item.target) }
        continue
      }
      let backup = try item.old.map { try backUp(item.target, matching: $0) }
      do { try fm.moveItem(at: item.file, to: item.target) }
      catch {
        if let backup, try inspect(item.target) == nil { try? fm.moveItem(at: backup, to: item.target) }
        throw error
      }
    }
  }
}

/// Direct output owns no staging folder. It never deletes the chosen root on
/// failure. Resolve every existing-file decision before starting the decoder.
final class DirectExtractionOutput {
  let directory: URL
  private var skipped = Set<String>()
  private var replacements: [String: stat] = [:]
  init(entries: [ArchiveEntry], directory: URL,
       conflict: (String) throws -> ExtractionConflictChoice) throws {
    self.directory = directory
    try ExtractionPublication.checkDirectory(directory)
    _ = try ArchiveSafety.validate(entries: entries, archiveBytes: 0)
    var replaceAll = false
    for entry in entries {
      try Task.checkCancellation()
      let target = directory.appendingPathComponent(try ArchiveSafety.outputPath(entry.path))
      try checkParent(target)
      if let old = try ExtractionPublication.inspect(target) {
        guard (old.st_mode & S_IFMT) == (entry.isDirectory ? S_IFDIR : S_IFREG),
              entry.isDirectory || old.st_nlink == 1 else { throw ArchiveFailure.unsafePath(entry.path) }
        if !entry.isDirectory {
          let choice = replaceAll ? ExtractionConflictChoice.replace : try conflict(entry.path)
          try Task.checkCancellation()
          switch choice {
          case .skip: skipped.insert(entry.path)
          case .cancel: throw CancellationError()
          case .replaceAll: replaceAll = true; replacements[entry.path] = old
          case .replace: replacements[entry.path] = old
          }
        }
      }
    }
  }
  private func checkParent(_ target: URL) throws {
    var parent = target.deletingLastPathComponent()
    while parent.path.count >= directory.path.count {
      if try ExtractionPublication.inspect(parent) != nil { try ExtractionPublication.checkDirectory(parent); return }
      parent.deleteLastPathComponent()
    }
    throw DestinationFailure.invalidDirectory
  }
  func shouldWrite(_ entry: ArchiveEntry) -> Bool { !skipped.contains(entry.path) }
  func prepare(_ entry: ArchiveEntry) throws {
    try Task.checkCancellation()
    let target = directory.appendingPathComponent(try ArchiveSafety.outputPath(entry.path))
    try checkParent(target)
    if let old = replacements[entry.path] {
      _ = try ExtractionPublication.backUp(target, matching: old)
      replacements.removeValue(forKey: entry.path)
    }
  }
}

enum DestinationKind: Equatable, Sendable {
  case appDocuments, iCloud, externalVolume, authorizedDirectory
}

/// Storage identity is descriptive, not an authorization decision. Only the
/// system picker/security scope, coordination and actual provider I/O authorize
/// access. Missing volume metadata must not reject Downloads or a USB provider.
enum DestinationPolicy {
  static func classify(
    inAppDocuments: Bool, isUbiquitous: Bool?,
    volumeIsLocal: Bool?, volumeIsInternal: Bool?, differentFromAppVolume: Bool? = nil,
    fileSystemIsLocal: Bool? = nil, isWritable: Bool? = nil
  ) throws -> DestinationKind {
    guard isWritable != false else { throw DestinationFailure.readOnly }
    if inAppDocuments { return .appDocuments }
    if isUbiquitous == true { return .iCloud }
    let local = volumeIsLocal == true || (volumeIsLocal == nil && fileSystemIsLocal == true)
    if local && (volumeIsInternal == false || (volumeIsInternal == nil && differentFromAppVolume == true)) { return .externalVolume }
    return .authorizedDirectory
  }

  static func validate(_ url: URL) throws -> DestinationKind {
    guard url.isFileURL else { throw DestinationFailure.invalidDirectory }
    var fresh = url; fresh.removeAllCachedResourceValues()
    let values = try fresh.resourceValues(forKeys: [
      .isDirectoryKey, .isSymbolicLinkKey,
      .isWritableKey, .isUbiquitousItemKey, .volumeIsLocalKey, .volumeIsInternalKey,
    ])
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw DestinationFailure.invalidDirectory
    }
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let root = documents.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    let candidate = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    return try classify(inAppDocuments: candidate.starts(with: root),
      isUbiquitous: values.isUbiquitousItem, volumeIsLocal: values.volumeIsLocal,
      volumeIsInternal: values.volumeIsInternal, isWritable: values.isWritable)
  }
}

enum DestinationFailure: LocalizedError {
  case invalidDirectory, readOnly, changed
  var errorDescription: String? {
    switch self {
    case .invalidDirectory:
      String(localized: "Choose an existing folder, not a file or symbolic link.")
    case .readOnly:
      String(localized: "This folder is read-only. Choose a writable destination in Files.")
    case .changed:
      String(localized: "The destination changed while awaiting a conflict decision. Please try again.")
    }
  }
}

struct ExtractionResult: Sendable {
  let directory: URL
  let destination: DestinationKind
}

extension CoordinatedFileAccess {
  /// The security grant and coordinated folder write cover the entire operation,
  /// including CRC verification, rename and rollback. Never persist the grant.
  static func extract(_ archive: ZIPArchive, paths: Set<String>, to pickedFolder: URL) throws
    -> ExtractionResult
  {
    try extract(.zip(archive), paths: paths, to: pickedFolder)
  }

  static func extract(_ archive: ArchiveContainer, paths: Set<String>, to pickedFolder: URL, password: String? = nil,
                      progress: @escaping ArchiveProgress = { _, _ in }, mergeExisting: Bool = false, useStaging: Bool = false,
                      conflict: (String) throws -> ExtractionConflictChoice = { _ in .skip }) throws
    -> ExtractionResult
  {
    let scoped = pickedFolder.startAccessingSecurityScopedResource()
    defer { if scoped { pickedFolder.stopAccessingSecurityScopedResource() } }
    try Task.checkCancellation()
    // Policy runs before any filesystem mutation, and again inside coordination.
    _ = try DestinationPolicy.validate(pickedFolder)
    var coordinationError: NSError?
    var result: Result<ExtractionResult, Error>?
    NSFileCoordinator().coordinate(
      writingItemAt: pickedFolder, options: [.forMerging], error: &coordinationError
    ) { folder in
      result = Result {
        try Task.checkCancellation()
        let kind = try DestinationPolicy.validate(folder)
        let directory = try archive.extractForUser(
          paths: paths, outputRoot: folder, createOutputRoot: false, password: password, progress: progress,
          mergeExisting: mergeExisting, useStaging: useStaging, conflict: conflict)
        return ExtractionResult(directory: directory, destination: kind)
      }
    }
    if let coordinationError { throw coordinationError }
    guard let result else { throw DestinationFailure.invalidDirectory }
    return try result.get()
  }
}
