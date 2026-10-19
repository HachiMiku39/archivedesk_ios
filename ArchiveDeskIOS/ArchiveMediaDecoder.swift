import Foundation
import CArchiveMedia

struct ArchiveMediaInfo: Sendable {
    let hasVideo: Bool, hasAudio: Bool
    let width: Int, height: Int
    let duration: Double
    let videoCodec: String, audioCodec: String
    let sampleRate: Int, channels: Int, bitRate: Int64
    let tags: [ArchiveMusicTag]
    let tagsLimited: Bool
}
struct ArchiveMusicTag: Sendable, Identifiable {
    let key: String, value: String
    var id: String { key }
    var title: String {
        switch key {
        case "title": String(localized: "Song title")
        case "artist": String(localized: "Artist")
        case "album": String(localized: "Album")
        case "album_artist", "albumartist": String(localized: "Album artist")
        case "track", "tracknumber": String(localized: "Track number")
        case "disc", "discnumber": String(localized: "Disc number")
        case "date", "year": String(localized: "Date / year")
        case "genre": String(localized: "Genre")
        case "composer": String(localized: "Composer")
        case "comment", "description": String(localized: "Comment")
        case "lyrics": String(localized: "Lyrics")
        case "copyright": String(localized: "Copyright")
        case "encoder": String(localized: "Encoder")
        default: key
        }
    }
}
struct ArchiveMediaFrame: Sendable {
    let kind: Int
    let bytes: Data
    let width: Int, height: Int, samples: Int
    let time: Double, duration: Double
}
enum MediaPreviewFailure: LocalizedError {
    case limit, backend(String)
    var errorDescription: String? {
        switch self {
        case .limit: String(localized: "This media exceeds the bounded preview limits. Extract it to open elsewhere.")
        case .backend(let detail): String(localized: "Open-source media decoding failed:") + " " + detail
        }
    }
}
private func mediaContinue(_ context: UnsafeMutableRawPointer?) -> Int32 { Task.isCancelled ? 0 : 1 }

/// One worker owns this decoder and serializes all calls; never concurrently
/// seek/decode/close. The bridge copies no entire compressed file into RAM.
final class ArchiveMediaDecoder: @unchecked Sendable {
    private var pointer: OpaquePointer?
    let info: ArchiveMediaInfo
    init(url: URL, videoMaxEdge: Int = 1280) throws {
        var pointer: OpaquePointer?, raw = ADMInfo()
        let result = url.withUnsafeFileSystemRepresentation { path in
            adm_open(path, mediaContinue, nil, &pointer, &raw)
        }
        do { try Self.check(result) } catch { adm_close(&pointer); throw error }
        guard let pointer else { throw MediaPreviewFailure.backend("No decoder") }
        self.pointer = pointer
        do {
            guard (160...1280).contains(videoMaxEdge) else { throw MediaPreviewFailure.limit }
            try Self.check(adm_video_output_limit(pointer, Int32(videoMaxEdge)))
        } catch { adm_close(&self.pointer); throw error }
        let video = withUnsafePointer(to: &raw.video_codec) { p in
            p.withMemoryRebound(to: CChar.self, capacity: 32) { String(cString: $0) }
        }
        let audio = withUnsafePointer(to: &raw.audio_codec) { p in
            p.withMemoryRebound(to: CChar.self, capacity: 32) { String(cString: $0) }
        }
        var tags: [ArchiveMusicTag] = [], limited = false, seen = Set<String>()
        for index in 0..<65 {
            var key = [CChar](repeating: 0, count: 128), value = [CChar](repeating: 0, count: 2049)
            let result = adm_metadata(pointer, UInt32(index), &key, key.count, &value, value.count)
            do { try Self.check(result) } catch { adm_close(&self.pointer); throw error }
            guard result > 0 else { break }
            if index == 64 { limited = true; break }
            limited = limited || result == 2
            let name = String(decoding: key.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self).lowercased()
            let text = String(decoding: value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !text.isEmpty, seen.insert(name).inserted { tags.append(ArchiveMusicTag(key: name, value: text)) }
        }
        let order = ["title", "artist", "album", "album_artist", "albumartist", "track", "tracknumber",
                     "disc", "discnumber", "date", "year", "genre", "composer", "comment", "description", "lyrics"]
        tags.sort { (order.firstIndex(of: $0.key) ?? 100, $0.key) < (order.firstIndex(of: $1.key) ?? 100, $1.key) }
        info = ArchiveMediaInfo(hasVideo: raw.has_video != 0, hasAudio: raw.has_audio != 0,
            width: Int(raw.width), height: Int(raw.height), duration: raw.duration, videoCodec: video, audioCodec: audio,
            sampleRate: Int(raw.sample_rate), channels: Int(raw.channels), bitRate: raw.bit_rate,
            tags: tags, tagsLimited: limited)
    }
    deinit { adm_close(&pointer) }
    func next() throws -> ArchiveMediaFrame? {
        try Task.checkCancellation()
        var frame = ADMFrame()
        let result = adm_next(pointer, &frame)
        try Self.check(result)
        guard result != 0 else { return nil }
        return try Self.copy(frame)
    }
    func artwork() throws -> ArchiveMediaFrame? {
        var frame = ADMFrame()
        let result = adm_artwork(pointer, &frame)
        try Self.check(result)
        return result == 0 ? nil : try Self.copy(frame)
    }
    private static func copy(_ frame: ADMFrame) throws -> ArchiveMediaFrame {
        guard let bytes = frame.data, frame.size > 0, frame.size <= 1280 * 1280 * 4 else { throw MediaPreviewFailure.limit }
        return ArchiveMediaFrame(kind: Int(frame.kind), bytes: Data(bytes: bytes, count: frame.size),
            width: Int(frame.width), height: Int(frame.height), samples: Int(frame.samples), time: frame.time, duration: frame.duration)
    }
    func seek(to seconds: Double) throws { try Self.check(adm_seek(pointer, seconds)) }
    private static func check(_ status: Int32) throws {
        try Task.checkCancellation()
        guard status < 0 else { return }
        var buffer = [CChar](repeating: 0, count: 256)
        adm_error(status, &buffer, buffer.count)
        throw MediaPreviewFailure.backend(String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
    }
}
