import Foundation

@main
struct MusicMetadataVerification {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        for name in ["tagged.mp3", "id3v24.mp3", "tagged.flac", "tagged.m4a"] {
            let decoder = try ArchiveMediaDecoder(url: root.appendingPathComponent(name))
            let tags = decoder.info.tags
            precondition(tags.first?.key == "title" && tags.first?.value == "星のうた · 测试曲")
            precondition(tags.first { $0.key == "artist" }?.value == "ArchiveDesk Artist")
            precondition(tags.first { $0.key == "track" }?.value == "3/12")
            precondition(tags.count == Set(tags.map(\.key)).count && !decoder.info.tagsLimited)
            precondition(decoder.info.hasAudio && !decoder.info.hasVideo)
            let art = try decoder.artwork(), audio = try decoder.next()
            precondition(art != nil && audio?.kind == 2)
        }
        let empty = try ArchiveMediaDecoder(url: root.appendingPathComponent("plain.wav"))
        precondition(empty.info.tags.isEmpty && !empty.info.tagsLimited)
        let noArt = try empty.artwork()
        precondition(noArt == nil)
        let limited = try ArchiveMediaDecoder(url: root.appendingPathComponent("long-tags.mp3"))
        precondition(limited.info.tagsLimited && limited.info.tags.count == 64)
        precondition(limited.info.tags.allSatisfy { $0.value.utf8.count <= 2051 })
        print("PASS Swift metadata normalization, ordering, empty state, artwork and display bounds")
    }
}
