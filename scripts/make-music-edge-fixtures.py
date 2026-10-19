"""Generate synthetic ID3 edge cases from the generated test MP3, never user files."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent / "work/music-tag-fixtures"
original = (root / "tagged.mp3").read_bytes()


def syncsafe(n):
    return bytes((n >> 21 & 127, n >> 14 & 127, n >> 7 & 127, n & 127))


size = 0
for byte in original[6:10]:
    size = size * 128 + byte
audio = original[10 + size :]


def frame(key, data):
    return key.encode("ascii") + syncsafe(len(data)) + b"\0\0" + data


def write(name, frames):
    tag = b"".join(frames)
    (root / name).write_bytes(b"ID3\x04\0\0" + syncsafe(len(tag)) + tag + audio)


title = frame("TIT2", b"\x03Artwork fallback")
write("broken-cover.mp3", [title, frame("APIC", b"\x03image/jpeg\0\x03\0" + b"not a JPEG" * 20)])
write("large-cover.mp3", [title, frame("APIC", b"\x03image/jpeg\0\x03\0" + (root / "cover.jpg").read_bytes() + b"\0" * (9 * 1024 * 1024))])
write("long-tags.mp3", [frame("TIT2", b"\x03" + ("长い标签" * 1000).encode())] + [
    frame("TXXX", b"\x03" + f"custom_{i:02}".encode() + b"\0test value") for i in range(70)
])
