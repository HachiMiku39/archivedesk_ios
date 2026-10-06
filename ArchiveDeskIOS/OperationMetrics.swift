import Foundation
import Darwin
import os

typealias ArchiveProgress = @Sendable (UInt64, UInt64) -> Void

/// A bounded mailbox, not one main-actor task per I/O chunk.
final class ProgressMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: UInt64 = 0
    private var total: UInt64 = 0
    func update(_ bytes: UInt64, _ total: UInt64) {
        lock.lock(); defer { lock.unlock() }
        self.bytes = bytes; self.total = total
    }
    func read() -> (bytes: UInt64, total: UInt64) {
        lock.lock(); defer { lock.unlock() }
        return (bytes, total)
    }
}

/// Extraction counts verified-destination writes, not skipped solid members.
/// The terminal callback is emitted only after verification and commit.
final class ExtractionProgress {
    private var bytes: UInt64 = 0
    private var lastReport = ProcessInfo.processInfo.systemUptime
    private let total: UInt64
    private let callback: ArchiveProgress
    init(total: UInt64, callback: @escaping ArchiveProgress) {
        self.total = total; self.callback = callback; callback(0, total)
    }
    func advance(_ count: Int) {
        bytes += UInt64(count)
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastReport >= 0.1 { callback(bytes, total); lastReport = now }
    }
    func complete() { callback(bytes, total) }
}

struct OperationMetrics: Equatable {
    var bytes: UInt64 = 0
    var total: UInt64 = 0
    var seconds: Double = 0
    var bytesPerSecond: Double = 0
    var succeeded = false
    var finished = false
    // Reading all bytes is not success: checksums, flush and rename still run.
    var fraction: Double? {
        if succeeded { return 1 }
        guard total > 0 else { return nil }
        return min(0.999, Double(bytes) / Double(total))
    }
}

struct TransferMeter {
    private let start: Double
    private var lastTime: Double
    private var lastBytes: UInt64 = 0
    init(now: Double = ProcessInfo.processInfo.systemUptime) { start = now; lastTime = now }
    mutating func sample(bytes: UInt64, total: UInt64, now: Double = ProcessInfo.processInfo.systemUptime,
                         finished: Bool = false, succeeded: Bool = false) -> OperationMetrics {
        let elapsed = max(0, now - start)
        let interval = max(0, now - lastTime)
        let delta = bytes >= lastBytes ? bytes - lastBytes : 0
        let speed = finished ? (elapsed > 0 ? Double(bytes) / elapsed : 0)
            : (interval > 0 ? Double(delta) / interval : 0)
        lastTime = now; lastBytes = bytes
        return OperationMetrics(bytes: bytes, total: total, seconds: elapsed,
                                bytesPerSecond: speed, succeeded: succeeded, finished: finished)
    }
}

struct ProcessMetrics: Sendable {
    var cpuPercent: Double?
    var memoryBytes: UInt64?
    var headroomBytes: UInt64?
}

struct ProcessSampler {
    private var previousCPU: Double?
    private var previousTime: Double?
    mutating func sample() -> ProcessMetrics {
        var cpu = task_absolutetime_info_data_t()
        var cpuCount = mach_msg_type_number_t(MemoryLayout.size(ofValue: cpu) / MemoryLayout<integer_t>.size)
        let cpuResult = withUnsafeMutablePointer(to: &cpu) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(cpuCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_ABSOLUTETIME_INFO), $0, &cpuCount)
            }
        }
        var scale = mach_timebase_info_data_t()
        mach_timebase_info(&scale)
        let now = ProcessInfo.processInfo.systemUptime
        let cpuSeconds = (Double(cpu.total_user) + Double(cpu.total_system)) * Double(scale.numer) / Double(max(1, scale.denom)) / 1e9
        var percent: Double?
        if cpuResult == KERN_SUCCESS {
            if let previousCPU, let previousTime, now > previousTime, cpuSeconds >= previousCPU {
                percent = (cpuSeconds - previousCPU) / (now - previousTime) * 100
            }
            previousCPU = cpuSeconds; previousTime = now
        } else { previousCPU = nil; previousTime = nil }
        var vm = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout.size(ofValue: vm) / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
            }
        }
        return ProcessMetrics(cpuPercent: percent,
                              memoryBytes: vmResult == KERN_SUCCESS ? vm.phys_footprint : nil,
                              headroomBytes: MemoryPolicy.headroom())
    }
}

enum MemoryPolicy {
    // Advisory snapshot, NOT a reservation or a guarantee against jetsam.
    static func headroom() -> UInt64? {
        #if os(iOS) && !targetEnvironment(simulator)
        return UInt64(os_proc_available_memory())
        #else
        return nil
        #endif
    }
    static func shouldStop(headroom: UInt64?) -> Bool { headroom.map { $0 < 64 * 1024 * 1024 } ?? false }
    static func allowsNewWork(headroom: UInt64?) -> Bool { headroom.map { $0 >= 192 * 1024 * 1024 } ?? true }
}
