import Foundation

struct MediaPreviewBudget: Equatable, Sendable {
    let memoryTierGB: Int
    let videoEdge: Int
    let imageEdge: Int
    let videoBytes: Int
    static func choose(physicalMemory: UInt64, headroom: UInt64?, lowPower: Bool, thermalLimited: Bool) -> Self {
        let gib: UInt64 = 1024 * 1024 * 1024
        let tier = physicalMemory <= 6 * gib ? 6 : physicalMemory <= 8 * gib ? 8 : physicalMemory <= 12 * gib ? 12 : 16
        let constrained = tier == 6 || lowPower || thermalLimited || headroom.map { $0 < 384 * 1024 * 1024 } == true
        return Self(memoryTierGB: tier, videoEdge: constrained ? 480 : 640,
                    imageEdge: constrained ? 1024 : 1280,
                    videoBytes: (constrained ? 6 : tier == 8 ? 8 : 12) * 1024 * 1024)
    }
}

/// Decoded surfaces only, never a whole-file cache. Owned by the main actor.
struct MediaVideoBuffer {
    static let maximumFrames = 12
    static let maximumBytes = 12 * 1024 * 1024
    private let byteLimit: Int
    init(byteLimit: Int = Self.maximumBytes) {
        precondition(byteLimit > 0 && byteLimit <= Self.maximumBytes)
        self.byteLimit = byteLimit
    }
    private var frames: [ArchiveMediaFrame] = []
    private(set) var bytes = 0
    var isEmpty: Bool { frames.isEmpty }
    var count: Int { frames.count }
    mutating func append(_ frame: ArchiveMediaFrame) throws -> Bool {
        guard frame.kind == 1, frame.time.isFinite, frame.duration.isFinite,
              frame.bytes.count <= byteLimit else { throw MediaPreviewFailure.limit }
        guard frames.count < Self.maximumFrames,
              frame.bytes.count <= byteLimit - bytes else { return false }
        frames.append(frame); bytes += frame.bytes.count
        return true
    }
    /// Keep the newest due surface if the UI missed a deadline. Future frames
    /// stay queued; presentation never waits inside the decoder's audio path.
    mutating func takeDue(at time: Double) -> (frame: ArchiveMediaFrame?, skipped: Int) {
        var due: ArchiveMediaFrame?, removed = 0
        while let first = frames.first, first.time <= time {
            due = frames.removeFirst(); bytes -= first.bytes.count; removed += 1
        }
        return (due, max(0, removed - 1))
    }
    mutating func removeAll() { frames.removeAll(keepingCapacity: false); bytes = 0 }
}

/// At most 32 small buffers / 32768 stereo frames (about 683 ms). A single
/// larger backend block is allowed alone, up to the existing 65536-frame cap.
final class MediaAudioBufferGate: @unchecked Sendable {
    private let lock = NSLock()
    private var samples = 0, buffers = 0
    var queuedSamples: Int { lock.lock(); defer { lock.unlock() }; return samples }
    func acquire(_ count: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard count > 0, count <= 65536, buffers < 32,
              buffers == 0 || count <= 32768 - samples else { return false }
        samples += count; buffers += 1; return true
    }
    func release(_ count: Int) {
        lock.lock(); defer { lock.unlock() }
        samples = max(0, samples - count); buffers = max(0, buffers - 1)
    }
}

struct MediaPlaybackTimebase {
    private var anchor = 0.0
    mutating func reset(position: Double, now: Double) { anchor = now - position }
    mutating func read(now: Double, audio: Double?) -> Double {
        if let audio, audio.isFinite, audio >= 0 { anchor = now - audio; return audio }
        return max(0, now - anchor)
    }
}
