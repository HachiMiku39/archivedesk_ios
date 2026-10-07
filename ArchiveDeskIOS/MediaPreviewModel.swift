import Foundation
import Combine
import CoreGraphics
import AVFAudio

private final class AudioPreviewGate: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func acquire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard count < 4 else { return false }; count += 1; return true
    }
    func release() { lock.lock(); count = max(0, count - 1); lock.unlock() }
}

/// Apple's engine only renders PCM decoded by FFmpeg. No AVPlayer, compressed
/// AVAudioFile, AudioToolbox codec or hardware decoder is used.
@MainActor
private final class AudioPreviewSink {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let gate = AudioPreviewGate()
    private let format: AVAudioFormat
    init() async throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false) else {
            throw MediaPreviewFailure.backend("PCM output format unavailable")
        }
        self.format = format
        #if os(iOS)
        // Session configuration/activation can wait on lower-priority audio
        // services. Never block the UI thread, including the iOS 26 fallback.
        try await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            if #available(iOS 27.0, *) {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    session.activate(options: []) { activated, error in
                        if let error { continuation.resume(throwing: error) }
                        else if activated { continuation.resume() }
                        else { continuation.resume(throwing: MediaPreviewFailure.backend("Audio session activation declined")) }
                    }
                }
            } else { try session.setActive(true) }
        }.value
        #endif
        try Task.checkCancellation()
        engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
    }
    func schedule(_ event: ArchiveMediaFrame) throws -> Bool {
        guard event.samples > 0, event.samples <= 65536, event.bytes.count == event.samples * 8 else { throw MediaPreviewFailure.limit }
        guard gate.acquire() else { return false }
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(event.samples)),
              let channels = pcm.floatChannelData else { gate.release(); throw MediaPreviewFailure.backend("PCM buffer unavailable") }
        pcm.frameLength = AVAudioFrameCount(event.samples)
        event.bytes.withUnsafeBytes { bytes in
            for i in 0..<event.samples {
                channels[0][i] = bytes.loadUnaligned(fromByteOffset: i * 8, as: Float.self)
                channels[1][i] = bytes.loadUnaligned(fromByteOffset: i * 8 + 4, as: Float.self)
            }
        }
        let gate = gate
        player.scheduleBuffer(pcm, completionCallbackType: .dataPlayedBack) { _ in gate.release() }
        if !player.isPlaying { player.play() }
        return true
    }
    func pause() { player.pause() }
    func resume() { if engine.isRunning { player.play() } }
    func stop() { player.stop(); engine.stop() }
    isolated deinit { player.stop(); engine.stop() }
}

struct MediaPreviewControl: Sendable {
    let playing: Bool, seekSerial: Int, target: Double, position: Double
}

@MainActor
final class MediaPreviewModel: ObservableObject {
    enum Phase { case empty, preparing, locked, ready, failed }
    @Published private(set) var phase = Phase.empty
    @Published private(set) var image: CGImage?
    @Published private(set) var info: ArchiveMediaInfo?
    @Published private(set) var kind: ArchivePreviewKind?
    @Published private(set) var isPlaying = false
    @Published private(set) var position = 0.0
    @Published private(set) var message: String?
    @Published private(set) var ended = false
    private(set) var generation = UUID()
    private var seekSerial = 0, target = 0.0, anchor = 0.0
    private var sink: AudioPreviewSink?

    @discardableResult
    func reset() -> UUID {
        generation = UUID(); sink?.stop(); sink = nil
        image = nil; info = nil; kind = nil; phase = .empty; message = nil
        isPlaying = false; position = 0; seekSerial = 0; target = 0; ended = false
        return generation
    }
    func preparing(_ kind: ArchivePreviewKind) { self.kind = kind; phase = .preparing }
    func lock(_ message: String? = nil) { phase = .locked; self.message = message }
    func ready(_ info: ArchiveMediaInfo, kind: ArchivePreviewKind, generation id: UUID) {
        guard generation == id else { return }
        self.info = info; self.kind = kind; phase = .ready
    }
    func fail(_ error: Error, generation id: UUID) {
        guard generation == id else { return }
        sink?.stop(); sink = nil; isPlaying = false; image = nil
        message = error.localizedDescription; phase = .failed
    }
    private var playhead: Double { isPlaying ? max(0, ProcessInfo.processInfo.systemUptime - anchor) : position }
    func control(generation id: UUID) -> MediaPreviewControl? {
        guard generation == id else { return nil }
        return MediaPreviewControl(playing: isPlaying, seekSerial: seekSerial, target: target, position: playhead)
    }
    func togglePlaying() {
        guard phase == .ready, kind != .image else { return }
        if isPlaying { position = playhead; isPlaying = false; sink?.pause() }
        else {
            if ended { seek(to: 0) }
            anchor = ProcessInfo.processInfo.systemUptime - position
            isPlaying = true; ended = false; sink?.resume()
        }
    }
    func seek(to seconds: Double) {
        guard phase == .ready, seconds.isFinite else { return }
        target = max(0, min(seconds, info?.duration ?? 86400))
        seekSerial += 1; position = target; anchor = ProcessInfo.processInfo.systemUptime - target
        ended = false; sink?.stop(); sink = nil
    }
    func show(_ frame: ArchiveMediaFrame, generation id: UUID) throws {
        guard generation == id else { return }
        guard frame.kind == 1, frame.width > 0, frame.height > 0,
              frame.bytes.count == frame.width * frame.height * 4,
              let provider = CGDataProvider(data: frame.bytes as CFData),
              let color = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: frame.width * 4, space: color,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw MediaPreviewFailure.limit }
        self.image = image
    }
    /// At most one event waits here. PCM scheduling also has a four-buffer cap.
    func consume(_ event: ArchiveMediaFrame, generation id: UUID, serial: Int) async throws {
        while generation == id && seekSerial == serial {
            try Task.checkCancellation()
            guard MemoryPolicy.headroom().map({ $0 >= 64 * 1024 * 1024 }) ?? true else { throw MediaPreviewFailure.limit }
            if !isPlaying { try await Task.sleep(for: .milliseconds(30)); continue }
            let advance = event.kind == 2 ? 0.2 : 0.0
            if event.time > playhead + advance { try await Task.sleep(for: .milliseconds(15)); continue }
            if event.kind == 1 {
                if event.time >= playhead - 0.25 { try show(event, generation: id) }
            } else {
                if sink == nil {
                    let candidate = try await AudioPreviewSink()
                    guard generation == id && seekSerial == serial else { candidate.stop(); return }
                    sink = candidate
                    if !isPlaying { candidate.pause(); continue }
                }
                if try sink?.schedule(event) != true { try await Task.sleep(for: .milliseconds(15)); continue }
            }
            position = (info?.duration ?? 0) > 0 ? min(info!.duration, playhead) : playhead
            return
        }
    }
    func finish(generation id: UUID, serial: Int) {
        guard generation == id && seekSerial == serial else { return }
        position = (info?.duration ?? 0) > 0 ? info!.duration : playhead; isPlaying = false; ended = true
        sink?.stop(); sink = nil
    }
}

enum MediaPreviewWorker {
    /// Called only on a detached serial worker after selected-entry extraction
    /// and archive integrity verification have completed.
    static func run(url: URL, kind: ArchivePreviewKind, model: MediaPreviewModel, generation id: UUID) async throws {
        let decoder = try ArchiveMediaDecoder(url: url)
        await model.ready(decoder.info, kind: kind, generation: id)
        if kind == .image || (kind == .video && decoder.info.hasVideo) {
            try await thumbnail(decoder, after: 0, model: model, id: id)
        }
        if kind == .image { return }
        // Thumbnail preparation can advance the stream; restart before playback.
        var serial = -1
        var lastEnd = 0.0
        while true {
            try Task.checkCancellation()
            guard let control = await model.control(generation: id) else { throw CancellationError() }
            if serial != control.seekSerial {
                try decoder.seek(to: control.target); serial = control.seekSerial
                lastEnd = control.target
                if kind == .video && !control.playing && decoder.info.hasVideo {
                    try await thumbnail(decoder, after: control.target, model: model, id: id)
                    // Start playback at the requested position, not after the thumbnail.
                    try decoder.seek(to: control.target)
                }
            }
            if !control.playing { try await Task.sleep(for: .milliseconds(40)); continue }
            if let event = try decoder.next() {
                lastEnd = max(lastEnd, event.time + event.duration)
                if event.time + event.duration >= control.target { try await model.consume(event, generation: id, serial: serial) }
            } else {
                // Drain the small PCM queue against the presentation clock.
                while let ending = await model.control(generation: id), ending.seekSerial == serial,
                      ending.position < max(decoder.info.duration, lastEnd) {
                    try await Task.sleep(for: .milliseconds(20)); try Task.checkCancellation()
                }
                await model.finish(generation: id, serial: serial)
            }
        }
    }
    private static func thumbnail(_ decoder: ArchiveMediaDecoder, after time: Double, model: MediaPreviewModel, id: UUID) async throws {
        for _ in 0..<4096 {
            try Task.checkCancellation()
            guard let event = try decoder.next() else { throw MediaPreviewFailure.backend("No video frame") }
            if event.kind == 1 && event.time + event.duration >= time {
                try await model.show(event, generation: id); return
            }
        }
        throw MediaPreviewFailure.limit
    }
}
