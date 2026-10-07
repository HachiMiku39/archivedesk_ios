import Foundation
import CArchiveMedia

struct ArchiveMediaInfo: Sendable {
    let hasVideo: Bool, hasAudio: Bool
    let width: Int, height: Int
    let duration: Double
    let videoCodec: String, audioCodec: String
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
    init(url: URL) throws {
        var pointer: OpaquePointer?, raw = ADMInfo()
        let result = url.withUnsafeFileSystemRepresentation { path in
            adm_open(path, mediaContinue, nil, &pointer, &raw)
        }
        try Self.check(result)
        guard let pointer else { throw MediaPreviewFailure.backend("No decoder") }
        self.pointer = pointer
        let video = withUnsafePointer(to: &raw.video_codec) { p in
            p.withMemoryRebound(to: CChar.self, capacity: 32) { String(cString: $0) }
        }
        let audio = withUnsafePointer(to: &raw.audio_codec) { p in
            p.withMemoryRebound(to: CChar.self, capacity: 32) { String(cString: $0) }
        }
        info = ArchiveMediaInfo(hasVideo: raw.has_video != 0, hasAudio: raw.has_audio != 0,
            width: Int(raw.width), height: Int(raw.height), duration: raw.duration, videoCodec: video, audioCodec: audio)
    }
    deinit { adm_close(&pointer) }
    func next() throws -> ArchiveMediaFrame? {
        try Task.checkCancellation()
        var frame = ADMFrame()
        let result = adm_next(pointer, &frame)
        try Self.check(result)
        guard result != 0 else { return nil }
        guard let bytes = frame.data, frame.size <= 1280 * 1280 * 4 else { throw MediaPreviewFailure.limit }
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
