import Foundation

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var c = UInt32(value)
        for _ in 0..<8 { c = (c & 1 == 1) ? 0xedb88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func update(_ current: UInt32 = 0, bytes: UnsafeRawBufferPointer) -> UInt32 {
        var crc = current ^ 0xffffffff
        for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8) }
        return crc ^ 0xffffffff
    }
    static func checksum(_ data: Data) -> UInt32 { data.withUnsafeBytes { update(bytes: $0) } }
}
