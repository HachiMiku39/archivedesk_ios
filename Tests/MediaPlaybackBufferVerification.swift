import Foundation

@main
struct MediaPlaybackBufferVerification {
    static func frame(_ time: Double, bytes: Int = 640 * 360 * 4) -> ArchiveMediaFrame {
        ArchiveMediaFrame(kind: 1, bytes: Data(count: bytes), width: 640, height: 360, samples: 0, time: time, duration: 1 / 30)
    }
    static func main() throws {
        let gib: UInt64 = 1024 * 1024 * 1024
        for (gb, edge, megabytes) in [(6, 480, 6), (8, 640, 8), (12, 640, 12), (16, 640, 12)] {
            let budget = MediaPreviewBudget.choose(physicalMemory: UInt64(gb) * gib, headroom: gib, lowPower: false, thermalLimited: false)
            precondition(budget.memoryTierGB == gb && budget.videoEdge == edge && budget.videoBytes == megabytes * 1024 * 1024)
        }
        for (headroom, lowPower, thermal) in [(UInt64(300 * 1024 * 1024), false, false), (gib, true, false), (gib, false, true)] {
            let budget = MediaPreviewBudget.choose(physicalMemory: 16 * gib, headroom: headroom, lowPower: lowPower, thermalLimited: thermal)
            precondition(budget.videoEdge == 480 && budget.imageEdge == 1024 && budget.videoBytes == 6 * 1024 * 1024)
        }
        let unknown = MediaPreviewBudget.choose(physicalMemory: 0, headroom: nil, lowPower: false, thermalLimited: false)
        precondition(unknown.memoryTierGB == 6 && unknown.videoEdge == 480)
        var compact = MediaVideoBuffer(byteLimit: 6 * 1024 * 1024)
        for index in 0..<12 { let accepted = try compact.append(frame(Double(index), bytes: 480 * 270 * 4)); precondition(accepted) }
        precondition(compact.bytes <= 6 * 1024 * 1024)
        print("PASS: 6/8/12/16 GiB policies, constrained headroom/power/thermal profiles and bounded six-GB video queue")
        var queue = MediaVideoBuffer()
        for index in 0..<12 { let accepted = try queue.append(frame(Double(index) / 30)); precondition(accepted) }
        let full = try queue.append(frame(1))
        precondition(!full && queue.count == 12 && queue.bytes == 12 * 640 * 360 * 4)
        let first = queue.takeDue(at: 0)
        precondition(first.frame?.time == 0 && first.skipped == 0)
        precondition(queue.takeDue(at: 0.01).frame == nil, "Future video must not be shown early")
        let late = queue.takeDue(at: 0.11)
        precondition(late.frame?.time == 0.1 && late.skipped == 2)
        queue.removeAll(); precondition(queue.isEmpty && queue.bytes == 0)
        let large = try queue.append(frame(0, bytes: MediaVideoBuffer.maximumBytes))
        let blocked = try queue.append(frame(1, bytes: 1))
        precondition(large && !blocked && queue.bytes == MediaVideoBuffer.maximumBytes)
        queue.removeAll()
        do { _ = try queue.append(frame(.nan)); fatalError("Invalid timestamp accepted") } catch MediaPreviewFailure.limit { }
        do { _ = try queue.append(frame(0, bytes: MediaVideoBuffer.maximumBytes + 1)); fatalError("Oversized frame accepted") } catch MediaPreviewFailure.limit { }
        print("PASS: bounded video count/bytes, future-frame retention, newest-due presentation, reset and invalid frame rejection")

        let gate = MediaAudioBufferGate()
        for _ in 0..<32 { precondition(gate.acquire(1024)) }
        precondition(gate.queuedSamples == 32768 && !gate.acquire(1024))
        gate.release(1024); precondition(gate.acquire(1024))
        for _ in 0..<32 { gate.release(1024) }
        precondition(gate.queuedSamples == 0 && gate.acquire(65536) && !gate.acquire(1))
        gate.release(65536)
        precondition(!gate.acquire(0) && !gate.acquire(65537))
        DispatchQueue.concurrentPerform(iterations: 10000) { _ in
            if gate.acquire(1024) { precondition(gate.queuedSamples <= 32768); gate.release(1024) }
        }
        precondition(gate.queuedSamples == 0)
        print("PASS: audio sample/count limits, isolated large block, release and concurrent backpressure")

        var clock = MediaPlaybackTimebase()
        clock.reset(position: 30, now: 100)
        precondition(clock.read(now: 101, audio: nil) == 31)
        precondition(clock.read(now: 101, audio: 30.2) == 30.2)
        precondition(abs(clock.read(now: 101.1, audio: nil) - 30.3) < 0.00001)
        clock.reset(position: 40, now: 1000) // Resume after a long pause.
        precondition(clock.read(now: 1001, audio: nil) == 41)
        precondition(clock.read(now: 1002, audio: .nan) == 42)
        print("PASS: audio-master clock, monotonic fallback anchor, pause/resume and invalid audio-clock fallback")
    }
}
