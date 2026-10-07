import CoreFoundation
import Foundation

/// Bounded random access: only a tail or one central/local record is in memory.
private final class ZIPReader {
  let handle: FileHandle
  let size: UInt64
  init(_ url: URL) throws {
    handle = try FileHandle(forReadingFrom: url)
    size = try handle.seekToEnd()
  }
  deinit { try? handle.close() }
  func read(at offset: UInt64, count: Int) throws -> Data {
    guard count >= 0, offset <= size, UInt64(count) <= size - offset else {
      throw ArchiveFailure.malformed("A ZIP record is outside the file.")
    }
    try handle.seek(toOffset: offset)
    let data = try autoreleasepool { try handle.read(upToCount: count) ?? Data() }
    guard data.count == count else { throw ArchiveFailure.malformed("A ZIP record is truncated.") }
    return data
  }
}

struct ZIPArchive: Sendable {
  let url: URL
  let entries: [ArchiveEntry]
  let dataBoundary: UInt64

  static func open(url: URL) throws -> ZIPArchive {
    let reader = try ZIPReader(url)
    guard reader.size >= 22 else {
      throw ArchiveFailure.malformed("The ZIP end record is missing.")
    }
    let tailSize = Int(min(reader.size, 65_557))
    let tailOffset = reader.size - UInt64(tailSize)
    let tail = try reader.read(at: tailOffset, count: tailSize)
    let end = stride(from: tail.count - 22, through: 0, by: -1).first {
      tail.u32($0) == 0x0605_4b50 && $0 + 22 + Int(tail.u16($0 + 20)) == tail.count
    }
    guard let end else { throw ArchiveFailure.malformed("The ZIP end record is missing.") }
    guard tail.u16(end + 4) == 0, tail.u16(end + 6) == 0,
      tail.u16(end + 8) == tail.u16(end + 10)
    else {
      throw ArchiveFailure.unsupported("Multi-disk ZIP archives are not supported.")
    }
    var count = UInt64(tail.u16(end + 10))
    var directorySize = UInt64(tail.u32(end + 12))
    var directoryOffset = UInt64(tail.u32(end + 16))
    var indexBoundary = tailOffset + UInt64(end)
    if count == 0xffff || directorySize == 0xffff_ffff || directoryOffset == 0xffff_ffff {
      guard indexBoundary >= 20 else {
        throw ArchiveFailure.malformed("The ZIP64 locator is missing.")
      }
      let locator = try reader.read(at: indexBoundary - 20, count: 20)
      guard locator.u32(0) == 0x0706_4b50, locator.u32(4) == 0, locator.u32(16) == 1 else {
        throw ArchiveFailure.unsupported("Invalid or multi-disk ZIP64 locator.")
      }
      indexBoundary = try locator.u64(8)
      let record = try reader.read(at: indexBoundary, count: 56)
      guard record.u32(0) == 0x0606_4b50, try record.u64(4) >= 44,
        record.u32(16) == 0, record.u32(20) == 0,
        try record.u64(24) == record.u64(32)
      else {
        throw ArchiveFailure.malformed("Invalid ZIP64 end record.")
      }
      count = try record.u64(32)
      directorySize = try record.u64(40)
      directoryOffset = try record.u64(48)
    }
    guard count <= UInt64(ArchiveSafety.maximumEntries), directoryOffset <= indexBoundary,
      directorySize <= indexBoundary - directoryOffset
    else {
      throw ArchiveFailure.malformed("The ZIP index is unreasonable.")
    }
    let directoryEnd = directoryOffset + directorySize
    var cursor = directoryOffset
    var entries: [ArchiveEntry] = []
    var indexedNameBytes = 0
    for index in 0..<Int(count) {
      try Task.checkCancellation()
      guard cursor <= directoryEnd, directoryEnd - cursor >= 46 else {
        throw ArchiveFailure.malformed("Truncated ZIP directory.")
      }
      let fixed = try reader.read(at: cursor, count: 46)
      guard fixed.u32(0) == 0x0201_4b50, fixed.u16(34) == 0 else {
        throw ArchiveFailure.malformed("Invalid ZIP directory record.")
      }
      let flags = fixed.u16(8)
      let method = fixed.u16(10)
      var compressed = UInt64(fixed.u32(20))
      var expanded = UInt64(fixed.u32(24))
      var local = UInt64(fixed.u32(42))
      let nameLength = Int(fixed.u16(28))
      let extraLength = Int(fixed.u16(30))
      let commentLength = Int(fixed.u16(32))
      indexedNameBytes += nameLength
      guard nameLength < ArchiveSafety.maximumPathBytes, indexedNameBytes <= 32 * 1_024 * 1_024
      else {
        throw ArchiveFailure.malformed("The ZIP filename index exceeds the memory budget.")
      }
      let variableLength = nameLength + extraLength + commentLength
      guard UInt64(variableLength) <= directoryEnd - cursor - 46 else {
        throw ArchiveFailure.malformed("Truncated ZIP filename/extra field.")
      }
      let variable = try reader.read(at: cursor + 46, count: variableLength)
      let nameData = variable.subdata(in: 0..<nameLength)
      let extra = variable.subdata(in: nameLength..<nameLength + extraLength)
      let fields = try extraFields(extra)
      if compressed == 0xffff_ffff || expanded == 0xffff_ffff || local == 0xffff_ffff {
        guard let zip64 = fields[1] else {
          throw ArchiveFailure.malformed("Missing ZIP64 entry values.")
        }
        var q = 0
        if expanded == 0xffff_ffff {
          expanded = try zip64.u64(q)
          q += 8
        }
        if compressed == 0xffff_ffff {
          compressed = try zip64.u64(q)
          q += 8
        }
        if local == 0xffff_ffff { local = try zip64.u64(q) }
      }
      let cp437 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
          CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue)))
      var name = String(data: nameData, encoding: flags & 0x800 != 0 ? .utf8 : cp437)
      if flags & 0x800 == 0, let unicode = fields[0x7075], unicode.count >= 5,
        unicode[0] == 1, unicode.u32(1) == CRC32.checksum(nameData)
      {
        guard let decoded = String(data: unicode.dropFirst(5), encoding: .utf8) else {
          throw ArchiveFailure.malformed("Invalid Unicode ZIP path.")
        }
        name = decoded
      }
      guard let name else { throw ArchiveFailure.malformed("Invalid ZIP filename encoding.") }
      _ = try ArchiveSafety.safeRelativePath(name)
      let unixType = (fixed.u32(38) >> 16) & 0xf000
      let isSpecial = unixType != 0 && unixType != 0x8000 && unixType != 0x4000
      guard local < directoryOffset || name.hasSuffix("/") else {
        throw ArchiveFailure.malformed("Invalid local header offset.")
      }
      entries.append(
        ArchiveEntry(
          id: index, path: name, compressedSize: compressed, uncompressedSize: expanded,
          crc32: fixed.u32(16), compressionMethod: method, localHeaderOffset: local, flags: flags,
          isLink: isSpecial, rawName: nameData))
      cursor += UInt64(46 + variableLength)
    }
    guard cursor == directoryEnd else {
      throw ArchiveFailure.malformed("The ZIP index length does not match its records.")
    }
    _ = try ArchiveSafety.validate(entries: entries, archiveBytes: reader.size)
    return ZIPArchive(url: url, entries: entries, dataBoundary: directoryOffset)
  }

  private static func extraFields(_ extra: Data) throws -> [UInt16: Data] {
    var result: [UInt16: Data] = [:]
    var cursor = 0
    while cursor < extra.count {
      guard extra.count - cursor >= 4 else {
        throw ArchiveFailure.malformed("Truncated ZIP extra field.")
      }
      let tag = extra.u16(cursor)
      let size = Int(extra.u16(cursor + 2))
      cursor += 4
      guard size <= extra.count - cursor, result[tag] == nil else {
        throw ArchiveFailure.malformed("Invalid ZIP extra field.")
      }
      result[tag] = extra.subdata(in: cursor..<cursor + size)
      cursor += size
    }
    return result
  }

  private func payloadOffset(_ entry: ArchiveEntry, reader: ZIPReader) throws -> UInt64 {
    guard entry.isExtractable else {
      throw ArchiveFailure.unsupported(
        entry.isEncrypted
          ? "Encrypted ZIP extraction is not available."
          : "This ZIP compression method is not available yet.")
    }
    let fixed = try reader.read(at: entry.localHeaderOffset, count: 30)
    guard fixed.u32(0) == 0x0403_4b50, fixed.u16(6) == entry.flags,
      fixed.u16(8) == entry.compressionMethod,
      entry.compressionMethod != 0 || entry.compressedSize == entry.uncompressedSize
    else { throw ArchiveFailure.malformed("ZIP headers or stored sizes disagree.") }
    let localName = try reader.read(at: entry.localHeaderOffset + 30, count: Int(fixed.u16(26)))
    guard localName == entry.rawName else {
      throw ArchiveFailure.malformed("ZIP local and central filenames disagree.")
    }
    let offset = entry.localHeaderOffset + 30 + UInt64(fixed.u16(26)) + UInt64(fixed.u16(28))
    guard offset <= dataBoundary, entry.compressedSize <= dataBoundary - offset else {
      throw ArchiveFailure.malformed("Truncated ZIP data.")
    }
    return offset
  }

  /// Use a fresh owned staging folder, then rename after all CRCs are verified.
  /// External callers must hold security scope and coordinate the destination.
  func extract(paths: Set<String>? = nil, outputRoot: URL, createOutputRoot: Bool = true,
               progress: @escaping ArchiveProgress = { _, _ in }) throws
    -> URL
  {
    let selected = entries.filter { paths == nil || paths!.contains($0.path) }
    guard selected.allSatisfy(\.isExtractable) else {
      throw ArchiveFailure.unsupported(
        "The selection contains encrypted or unsupported ZIP entries.")
    }
    let total = try ArchiveSafety.validate(entries: selected, archiveBytes: 0)
    let meter = ExtractionProgress(total: total, callback: progress)
    try Task.checkCancellation()
    if createOutputRoot {
      try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
    }
    let rootValues = try outputRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
      throw DestinationFailure.invalidDirectory
    }
    try StorageBudget.require(total + 16 * 1_024 * 1_024, at: outputRoot)
    let staging = outputRoot.appendingPathComponent(
      ".ArchiveDesk-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
    do {
      let reader = try ZIPReader(url)
      for entry in selected {
        try Task.checkCancellation()
        let output = staging.appendingPathComponent(try ArchiveSafety.outputPath(entry.path))
        if entry.isDirectory {
          try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
          continue
        }
        var offset = try payloadOffset(entry, reader: reader)
        try FileManager.default.createDirectory(
          at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try StorageBudget.createFile(at: output)
        let handle = try FileHandle(forWritingTo: output)
        do {
          if entry.compressionMethod == 8 {
            try NativeArchiveReader.stream(entry, from: url) {
              try handle.write(contentsOf: $0); meter.advance($0.count)
            }
            try handle.synchronize()
            try handle.close()
            continue
          }
          var remaining = entry.uncompressedSize
          var crc: UInt32 = 0
          while remaining > 0 {
            try Task.checkCancellation()
            let chunk = try reader.read(at: offset, count: Int(min(remaining, 256 * 1_024)))
            crc = chunk.withUnsafeBytes { CRC32.update(crc, bytes: $0) }
            try autoreleasepool { try handle.write(contentsOf: chunk) }
            meter.advance(chunk.count)
            offset += UInt64(chunk.count)
            remaining -= UInt64(chunk.count)
          }
          guard crc == entry.crc32 else { throw ArchiveFailure.crcMismatch(entry.path) }
          try handle.synchronize()
          try handle.close()
        } catch {
          try? handle.close()
          throw error
        }
      }
      try Task.checkCancellation()
      let final = outputRoot.appendingPathComponent(
        "Extracted-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.moveItem(at: staging, to: final)
      meter.complete()
      return final
    } catch {
      let originalError = error
      do { try FileManager.default.removeItem(at: staging) } catch {
        // A disconnected/read-only drive can prevent rollback. Never claim
        // complete cleanup, or delete anything beyond our UUID staging folder.
        throw ExtractionRollbackFailure(
          stagingFolder: staging.lastPathComponent, cause: originalError.localizedDescription)
      }
      throw originalError
    }
  }

  func previewText(_ entry: ArchiveEntry) throws -> String? {
    guard !entry.isDirectory, entry.isExtractable, entry.uncompressedSize <= 256 * 1_024 else {
      return nil
    }
    let extensions = ["txt", "md", "json", "xml", "csv", "log", "swift", "plist", "yaml", "yml"]
    guard extensions.contains((entry.path as NSString).pathExtension.lowercased()) else {
      return nil
    }
    let reader = try ZIPReader(url)
    if entry.compressionMethod == 8 {
      _ = try payloadOffset(entry, reader: reader)
      var bytes = Data()
      try NativeArchiveReader.stream(entry, from: url) { bytes.append($0) }
      return ArchiveTextPreview.decode(bytes)
    }
    let bytes = try reader.read(
      at: payloadOffset(entry, reader: reader), count: Int(entry.uncompressedSize))
    try Task.checkCancellation()
    guard CRC32.checksum(bytes) == entry.crc32 else { throw ArchiveFailure.crcMismatch(entry.path) }
    return ArchiveTextPreview.decode(bytes)
  }
}

struct ExtractionRollbackFailure: LocalizedError {
  let stagingFolder: String
  let cause: String
  var packing = false
  var errorDescription: String? {
    (packing ? String(localized: "Archive creation failed and the temporary folder could not be removed. Reconnect the drive and remove only this unfinished folder:") : String(
      localized:
        "Extraction failed and the temporary folder could not be removed. Reconnect the drive and remove only this unfinished folder:"
    ))
      + " " + stagingFolder + "\n" + cause
  }
}

extension Data {
  fileprivate func u16(_ offset: Int) -> UInt16 {
    UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
  }
  fileprivate func u32(_ offset: Int) -> UInt32 {
    UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16
  }
  fileprivate func u64(_ offset: Int) throws -> UInt64 {
    guard offset >= 0, offset <= count, count - offset >= 8 else {
      throw ArchiveFailure.malformed("A ZIP64 value is truncated.")
    }
    return UInt64(u32(offset)) | UInt64(u32(offset + 4)) << 32
  }
}
