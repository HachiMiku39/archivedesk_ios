import Foundation

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
  case invalidDirectory, readOnly
  var errorDescription: String? {
    switch self {
    case .invalidDirectory:
      String(localized: "Choose an existing folder, not a file or symbolic link.")
    case .readOnly:
      String(localized: "This folder is read-only. Choose a writable destination in Files.")
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
                      progress: @escaping ArchiveProgress = { _, _ in }) throws
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
        let directory = try archive.extract(
          paths: paths, outputRoot: folder, createOutputRoot: false, password: password, progress: progress)
        return ExtractionResult(directory: directory, destination: kind)
      }
    }
    if let coordinationError { throw coordinationError }
    guard let result else { throw DestinationFailure.invalidDirectory }
    return try result.get()
  }
}
