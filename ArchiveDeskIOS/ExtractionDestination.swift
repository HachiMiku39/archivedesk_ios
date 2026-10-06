import Foundation

enum DestinationKind: Equatable, Sendable {
  case appDocuments, iCloud, externalVolume
}

/// Do not confuse a provider's local cache with an on-device destination.
/// iOS does not expose a general third-party provider identity for picked URLs.
/// Unknown destinations therefore fail closed, without even a test write.
enum DestinationPolicy {
  static func classify(
    inAppDocuments: Bool, isUbiquitous: Bool?,
    volumeIsLocal: Bool?, volumeIsInternal: Bool?
  ) throws -> DestinationKind {
    if inAppDocuments { return .appDocuments }
    if isUbiquitous == true { return .iCloud }
    if volumeIsLocal == true && volumeIsInternal == false { return .externalVolume }
    throw DestinationFailure.unidentifiedProvider
  }

  static func validate(_ url: URL) throws -> DestinationKind {
    guard url.isFileURL else { throw DestinationFailure.invalidDirectory }
    let values = try url.resourceValues(forKeys: [
      .isDirectoryKey, .isSymbolicLinkKey,
      .isWritableKey, .isUbiquitousItemKey, .volumeIsLocalKey, .volumeIsInternalKey,
    ])
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw DestinationFailure.invalidDirectory
    }
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let root = documents.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    let candidate = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    let kind = try classify(
      inAppDocuments: candidate.starts(with: root),
      isUbiquitous: values.isUbiquitousItem, volumeIsLocal: values.volumeIsLocal,
      volumeIsInternal: values.volumeIsInternal)
    guard values.isWritable != false else { throw DestinationFailure.readOnly }
    return kind
  }
}

enum DestinationFailure: LocalizedError {
  case unidentifiedProvider, invalidDirectory, readOnly
  var errorDescription: String? {
    switch self {
    case .unidentifiedProvider:
      String(
        localized:
          "This location cannot be verified as local storage, an external drive, or iCloud. Third-party cloud drives are read-only. Choose another destination."
      )
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
