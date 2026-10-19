import Foundation
import Combine
import CoreGraphics
import AVFAudio

/// Apple's engine only renders PCM decoded by FFmpeg. No AVPlayer, compressed
/// AVAudioFile, AudioToolbox codec or hardware decoder is used.
@MainActor
private final class AudioPreviewSink {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let gate = MediaAudioBufferGate()
    private let format: AVAudioFormat
    private var firstPTS: Double?
    private(set) var started = false
    private(set) var starvations = 0
    var hasPending: Bool { gate.queuedSamples > 0 }
    var presentationTime: Double? {
        guard started, hasPending, let firstPTS, let rendered = player.lastRenderTime,
              let played = player.playerTime(forNodeTime: rendered), played.isSampleTimeValid,
              played.sampleRate > 0 else { return nil }
        return firstPTS + max(0, Double(played.sampleTime) / played.sampleRate)
    }
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
        let wasEmpty = !hasPending
        guard gate.acquire(event.samples) else { return false }
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(event.samples)),
              let channels = pcm.floatChannelData else { gate.release(event.samples); throw MediaPreviewFailure.backend("PCM buffer unavailable") }
        pcm.frameLength = AVAudioFrameCount(event.samples)
        event.bytes.withUnsafeBytes { bytes in
            for i in 0..<event.samples {
                channels[0][i] = bytes.loadUnaligned(fromByteOffset: i * 8, as: Float.self)
                channels[1][i] = bytes.loadUnaligned(fromByteOffset: i * 8 + 4, as: Float.self)
            }
        }
        if firstPTS == nil { firstPTS = event.time }
        if started && wasEmpty { starvations += 1 }
        let gate = gate, samples = event.samples
        player.scheduleBuffer(pcm, completionCallbackType: .dataPlayedBack) { _ in gate.release(samples) }
        // Pre-roll about 85 ms of small AAC blocks instead of starting with a
        // single ~21 ms packet. EOF explicitly starts shorter clips as well.
        if gate.queuedSamples >= 4096 { startPending() }
        return true
    }
    func startPending() {
        guard hasPending, !player.isPlaying else { return }
        player.play(); started = true
    }
    func pause() { player.pause() }
    func resume() { if engine.isRunning && started { startPending() } }
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
    @Published private(set) var artworkUnavailable = false
    private(set) var generation = UUID()
    private var seekSerial = 0, target = 0.0
    private var timebase = MediaPlaybackTimebase()
    private var sink: AudioPreviewSink?
    private var videoBuffer = MediaVideoBuffer()
    private var presentationTask: Task<Void, Never>?
    private var submittedFrames = 0, skippedFrames = 0
    private let displayColorSpace = CGColorSpace(name: CGColorSpace.sRGB)

    @discardableResult
    func reset() -> UUID {
        generation = UUID(); presentationTask?.cancel(); presentationTask = nil
        sink?.stop(); sink = nil; videoBuffer.removeAll()
        image = nil; info = nil; kind = nil; phase = .empty; message = nil
        isPlaying = false; position = 0; seekSerial = 0; target = 0; ended = false
        artworkUnavailable = false
        submittedFrames = 0; skippedFrames = 0
        return generation
    }
    func preparing(_ kind: ArchivePreviewKind) { self.kind = kind; phase = .preparing }
    func lock(_ message: String? = nil) { phase = .locked; self.message = message }
    func ready(_ info: ArchiveMediaInfo, kind: ArchivePreviewKind, budget: MediaPreviewBudget, generation id: UUID) {
        guard generation == id else { return }
        videoBuffer = MediaVideoBuffer(byteLimit: budget.videoBytes)
        self.info = info; self.kind = kind; phase = .ready
    }
    private func startPresentation() {
        let id = generation
        presentationTask?.cancel()
        presentationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { guard try self?.presentTick(generation: id) == true else { return } }
                catch { self?.fail(error, generation: id); return }
                do { try await Task.sleep(for: .milliseconds(12)) } catch { return }
            }
        }
    }
    func fail(_ error: Error, generation id: UUID) {
        guard generation == id else { return }
        presentationTask?.cancel(); presentationTask = nil; videoBuffer.removeAll()
        sink?.stop(); sink = nil; isPlaying = false; image = nil
        message = error.localizedDescription; phase = .failed
    }
    func skipArtwork(generation id: UUID) {
        guard generation == id else { return }
        artworkUnavailable = true
    }
    private var playhead: Double {
        guard isPlaying else { return position }
        return timebase.read(now: ProcessInfo.processInfo.systemUptime, audio: sink?.presentationTime)
    }
    func control(generation id: UUID) -> MediaPreviewControl? {
        guard generation == id, phase == .ready else { return nil }
        return MediaPreviewControl(playing: isPlaying, seekSerial: seekSerial, target: target, position: playhead)
    }
    func togglePlaying() {
        guard phase == .ready, kind != .image else { return }
        if isPlaying {
            position = playhead; isPlaying = false; sink?.pause()
            presentationTask?.cancel(); presentationTask = nil
        }
        else {
            if ended { seek(to: 0) }
            timebase.reset(position: position, now: ProcessInfo.processInfo.systemUptime)
            isPlaying = true; ended = false; sink?.resume()
            startPresentation()
        }
    }
    func seek(to seconds: Double) {
        guard phase == .ready, seconds.isFinite else { return }
        target = max(0, min(seconds, info?.duration ?? 86400))
        seekSerial += 1; position = target
        timebase.reset(position: target, now: ProcessInfo.processInfo.systemUptime)
        ended = false; sink?.stop(); sink = nil; videoBuffer.removeAll()
    }
    func show(_ frame: ArchiveMediaFrame, generation id: UUID) throws {
        guard generation == id else { return }
        guard frame.kind == 1, frame.width > 0, frame.height > 0,
              frame.bytes.count == frame.width * frame.height * 4,
              let provider = CGDataProvider(data: frame.bytes as CFData),
              let color = displayColorSpace,
              let image = CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: frame.width * 4, space: color,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw MediaPreviewFailure.limit }
        self.image = image
    }
    private func presentTick(generation id: UUID) throws -> Bool {
        guard generation == id, phase == .ready else { return false }
        guard isPlaying else { return true }
        let clock = playhead
        let due = videoBuffer.takeDue(at: clock)
        if let frame = due.frame {
            try show(frame, generation: id); submittedFrames += 1; skippedFrames += due.skipped
        }
        let current = (info?.duration ?? 0) > 0 ? min(info!.duration, clock) : clock
        // Audio packets need not invalidate the entire SwiftUI form ~47 times/s.
        if abs(current - position) >= 0.1 { position = current }
        return true
    }
    /// Bounded look-ahead; video presentation does not block following audio.
    func consume(_ event: ArchiveMediaFrame, generation id: UUID, serial: Int) async throws {
        while generation == id && seekSerial == serial {
            try Task.checkCancellation()
            guard MemoryPolicy.headroom().map({ $0 >= 64 * 1024 * 1024 }) ?? true else { throw MediaPreviewFailure.limit }
            if !isPlaying { try await Task.sleep(for: .milliseconds(30)); continue }
            if event.kind == 1 {
                if try !videoBuffer.append(event) { try await Task.sleep(for: .milliseconds(5)); continue }
            } else {
                if event.time > playhead + 0.35 { try await Task.sleep(for: .milliseconds(5)); continue }
                if sink == nil {
                    let candidate = try await AudioPreviewSink()
                    guard generation == id && seekSerial == serial else { candidate.stop(); return }
                    sink = candidate
                    if !isPlaying { candidate.pause(); continue }
                }
                if try sink?.schedule(event) != true { try await Task.sleep(for: .milliseconds(5)); continue }
            }
            return
        }
    }
    func drain(generation id: UUID, serial: Int, end: Double) -> Bool {
        guard generation == id, phase == .ready, seekSerial == serial else { return true }
        guard isPlaying else { return false }
        sink?.startPending()
        guard videoBuffer.isEmpty, sink?.hasPending != true, playhead >= end - 0.03 else { return false }
        if ProcessInfo.processInfo.arguments.contains("--media-diagnostics") {
            print("Media presentation submitted=\(submittedFrames) skipped=\(skippedFrames) audioStarvations=\(sink?.starvations ?? 0)")
        }
        position = (info?.duration ?? 0) > 0 ? min(info!.duration, end) : end; isPlaying = false; ended = true
        presentationTask?.cancel(); presentationTask = nil
        sink?.stop(); sink = nil
        return true
    }
}

enum MediaPreviewWorker {
    /// Called only on a detached serial worker after selected-entry extraction
    /// and archive integrity verification have completed.
    static func run(url: URL, kind: ArchivePreviewKind, model: MediaPreviewModel, generation id: UUID) async throws {
        // Inline video is a small preview, not a full-screen player. Quarter
        // the 1280×720 RGBA surface/copy size without lowering the frame rate.
        let process = ProcessInfo.processInfo
        var physicalMemory = process.physicalMemory
        #if DEBUG && targetEnvironment(simulator)
        if let argument = process.arguments.first(where: { $0.hasPrefix("--preview-memory-gb=") }),
           let gb = UInt64(argument.dropFirst("--preview-memory-gb=".count)), [6, 8, 12, 16].contains(gb) {
            physicalMemory = gb * 1024 * 1024 * 1024
        }
        #endif
        let budget = MediaPreviewBudget.choose(physicalMemory: physicalMemory, headroom: MemoryPolicy.headroom(),
            lowPower: process.isLowPowerModeEnabled, thermalLimited: process.thermalState == .serious || process.thermalState == .critical)
        let decoder = try ArchiveMediaDecoder(url: url, videoMaxEdge: kind == .video ? budget.videoEdge : budget.imageEdge)
        await model.ready(decoder.info, kind: kind, budget: budget, generation: id)
        if kind == .audio {
            do {
                guard MemoryPolicy.headroom().map({ $0 >= 64 * 1024 * 1024 }) ?? true else { throw MediaPreviewFailure.limit }
                if let cover = try decoder.artwork() { try await model.show(cover, generation: id) }
            } catch is CancellationError { throw CancellationError() }
            catch { await model.skipArtwork(generation: id) }
        }
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
            if !control.playing { try await Task.sleep(for: .milliseconds(150)); continue }
            if let event = try decoder.next() {
                lastEnd = max(lastEnd, event.time + event.duration)
                if event.time + event.duration >= control.target { try await model.consume(event, generation: id, serial: serial) }
            } else {
                // Wait for actual submitted media, not just a wall-clock duration.
                while await !model.drain(generation: id, serial: serial, end: lastEnd) {
                    try await Task.sleep(for: .milliseconds(10)); try Task.checkCancellation()
                }
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
