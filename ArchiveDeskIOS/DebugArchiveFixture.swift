#if DEBUG
import Foundation

/// Deterministic, local-only data for Simulator/debug sessions. No ZIP creation
/// capability is exposed by the product until a production writer is verified.
enum DebugArchiveFixture {
    static func bytes(_ records: [(String, Data)]) -> Data {
        var archive = Data(), directory = Data()
        for (name, payload) in records {
            let rawName = Data(name.utf8), crc = CRC32.checksum(payload), offset = archive.count
            archive.le32(0x04034b50); archive.le16(20); archive.le16(0x800); archive.le16(0); archive.le16(0); archive.le16(0)
            archive.le32(crc); archive.le32(UInt32(payload.count)); archive.le32(UInt32(payload.count))
            archive.le16(UInt16(rawName.count)); archive.le16(0); archive.append(rawName); archive.append(payload)
            directory.le32(0x02014b50); directory.le16(20); directory.le16(20); directory.le16(0x800); directory.le16(0); directory.le16(0); directory.le16(0)
            directory.le32(crc); directory.le32(UInt32(payload.count)); directory.le32(UInt32(payload.count))
            directory.le16(UInt16(rawName.count)); directory.le16(0); directory.le16(0); directory.le16(0); directory.le16(0)
            directory.le32(0); directory.le32(UInt32(offset)); directory.append(rawName)
        }
        let offset = archive.count
        archive.append(directory)
        archive.le32(0x06054b50); archive.le16(0); archive.le16(0); archive.le16(UInt16(records.count)); archive.le16(UInt16(records.count))
        archive.le32(UInt32(directory.count)); archive.le32(UInt32(offset)); archive.le16(0)
        return archive
    }

    static func create() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveDesk-Debug-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let kind = ProcessInfo.processInfo.arguments.first(where: { $0 == "--fixture-7z" || $0 == "--fixture-deflate" || $0 == "--fixture-cp437" }) {
            let is7z = kind == "--fixture-7z"
            let encoded = is7z
                ? "N3q8ryccAAQKE/GxUwEAAAAAAAAjAAAAAAAAAFK22V7gAXkAnV0AEYgGSIIBw39DfCCmhq1Qth8OMWgOqvqHeNgLDFPHEKt/xZYn69JcmyMW81EO4VXknBw3OTuBN0NBAK+ZfJH7czlupFD+Hq3dDlkA4y9NNjT0sHWupYC7/8Lr1tXqv8QikuK/HmBprgQ5vXyl/w0OQEyH0n2XND4Y4PuhpJmj0LKDF2kblVyPP+xQHWN1pv04pbMKKnbIl1rnKrPc7gAAAIEzB64P1TB5Vlck0/6zcBiBQB5Fw0kcia4wGzNGfbbgZTgs1tubU1GpkO1LVOzKPUoWDqng+HaqQzUR7zb9+Mo1fMFUGThUeN9gpRVIw0HTnVjPH9xebbJidsHbkrYDLw+uFeYcYHa6mv/WleysXwHnNRRAQRy/rG3k5NoQJgZKYQxvLmnP59mOkKxdnYMp/Ddwl3NBgCXv6rQsyN594WnyxiZVovHsZYYAAAAXBoClAQmArgAHCwEAASMDAQEFXQAQAAAMgOIKAV9mtDUAAA=="
                : "UEsDBBQAAAAIAMFZRF0bM50vaQAAAPQAAAAIAAAATm90ZXMubWTNyjEOQDAUgOG9p2hidweJ2R2knmgkmiBmvMFmkbCIzSKYO7jNaxrH0GPY/vz5PB6pGirGglJksoEQqpwXce2SC5WA4A2UMpXCLVX4v2ZGX3YejB7tstv1fI+NuptwITwJJ8Kd8KG2Zx9QSwMECgAAAAAAaFlEXQAAAAAAAAAAAAAAAAkAAABlbXB0eS50eHRQSwECPwMUAAAACADBWURdGzOdL2kAAAD0AAAACAAkAAAAAAAAACCApIEAAAAATm90ZXMubWQKACAAAAAAAAEAGADEOIxmrlPdAQAAAAAAAAAAAAAAAAAAAABQSwECPwMKAAAAAABoWURdAAAAAAAAAAAAAAAACQAkAAAAAAAAACCApIGPAAAAZW1wdHkudHh0CgAgAAAAAAABABgAgjNuBK5T3QEAAAAAAAAAAAAAAAAAAAAAUEsFBgAAAAACAAIAtQAAALYAAAAAAA=="
            let url = directory.appendingPathComponent(is7z ? "Native Sample.7z" : "Deflate Sample.zip")
            var data = Data(base64Encoded: encoded)!
            if kind == "--fixture-cp437" {
                let central = data.range(of: Data([0x50, 0x4b, 0x01, 0x02]))!.lowerBound
                data[30] = 0x82; data[central + 46] = 0x82
                data[7] &= 0xf7; data[central + 9] &= 0xf7
            }
            try data.write(to: url)
            return url
        }
        let url = directory.appendingPathComponent("Duo Sample.zip")
        try bytes([
            ("Readme.txt", Data("ArchiveDesk\n\nOpen a folder, select a file, and change the window size. Your archive, selection, preview, and task should remain available.\n".utf8)),
            ("Documents/Notes.md", Data("# Notes\n\nA small UTF-8 preview.\n".utf8)),
            ("Documents/日本語.txt", Data("アーカイブのプレビュー。\n".utf8)),
            ("Documents/中文.txt", Data("归档预览与文件选择状态。\n".utf8))
        ]).write(to: url)
        return url
    }
}

private extension Data {
    mutating func le16(_ value: UInt16) { append(UInt8(value & 0xff)); append(UInt8(value >> 8)) }
    mutating func le32(_ value: UInt32) { le16(UInt16(value & 0xffff)); le16(UInt16(value >> 16)) }
}
#endif
