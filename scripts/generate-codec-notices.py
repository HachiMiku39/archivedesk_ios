"""Mechanical aggregation of unmodified upstream license headers and texts."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
sources = root / "work/codec-sources"
archive = sources / "libarchive-3.8.9"
xz = sources / "xz-5.8.4"
parts = ["ArchiveDesk native archive codecs\n\nlibarchive 3.8.9: https://www.libarchive.org/\nXZ Utils / liblzma 5.8.4: https://tukaani.org/xz/\n\nNo 7-Zip command-line binary is shipped. The following upstream license texts and source-file notices are reproduced verbatim. Per-file terms control.\n"]
for source in [archive / "COPYING", xz / "COPYING", xz / "COPYING.0BSD"]:
    parts.append(str(source.relative_to(sources)) + "\n\n" + source.read_text())
for source in sorted((archive / "libarchive").iterdir()):
    if source.suffix not in (".c", ".h"):
        continue
    text = source.read_text()
    begin, end = text.find("/*"), text.find("*/")
    if 0 <= begin < end:
        parts.append(source.name + "\n" + text[begin:end + 2])
rar = root / "work/rar-sources"
parts.append("7-Zip 26.03 source RAR decoder and UDF read-only image handler: https://github.com/ip7z/7zip\nArchiveDesk RAR/UDF bridge: LGPL-2.1-or-later. RAR creation is not provided. UDF metadata budgets are applied to UdfIn.cpp. See docs/RAR-LICENSE-AND-RELINK.md for modifications and relinking requirements.")
for name in ["License.txt", "copying.txt", "unRarLicense.txt"]:
    parts.append("7-Zip/DOC/" + name + "\n\n" + (rar / "DOC" / name).read_text())
media = root / "work/media-sources"
ffmpeg = media / "ffmpeg-9.0.2"
dav1d = media / "dav1d-1.5.4"
parts.append("FFmpeg 9.0.2: https://ffmpeg.org/ — LGPL-2.1-or-later build; GPL, version3 and nonfree components disabled. No FFmpeg CLI, system media codec or hardware decoder is shipped. dav1d 1.5.4: https://code.videolan.org/videolan/dav1d — BSD-2-Clause. Full corresponding source archives, bridge and build recipe are distributed with the application source; matching static libraries and application objects permit relinking. This software is based in part on the work of the Independent JPEG Group. FFmpeg's libjpeg-derived files are unmodified.")
for source in [ffmpeg / "LICENSE.md", ffmpeg / "COPYING.LGPLv2.1", dav1d / "COPYING", ffmpeg / "libavcodec/jrevdct.c"]:
    text = source.read_text()
    if source.suffix == ".c":
        end = text.find("*/")
        text = text[:end + 2]
    parts.append(str(source.relative_to(media)) + "\n\n" + text)
notice_sources = set()
for obj in (root / "work/media-codecs/ios-arm64/ffmpeg").rglob("*.o"):
    relative = obj.relative_to(root / "work/media-codecs/ios-arm64/ffmpeg")
    for suffix in (".c", ".S", ".asm"):
        candidate = ffmpeg / relative.with_suffix(suffix)
        if candidate.is_file():
            notice_sources.add(candidate)
for name in ("libavcodec", "libavformat", "libavutil", "libswscale", "libswresample", "compat"):
    notice_sources.update((ffmpeg / name).rglob("*.h"))
for source in dav1d.rglob("*"):
    if source.is_file() and source.suffix in (".c", ".h", ".S", ".asm"):
        notice_sources.add(source)
parts.append("Additional upstream source-file copyright notices (compiled FFmpeg sources and library headers; dav1d source notices). Inclusion of a notice does not imply that every optional upstream component is linked.")
for source in sorted(notice_sources):
    text = source.read_text(errors="replace")
    begin, end = text.find("/*"), text.find("*/")
    if 0 <= begin < end:
        parts.append(str(source.relative_to(media)) + "\n" + text[begin:end + 2])
    elif source.suffix == ".asm":
        header = []
        for line in text.splitlines():
            if not line.strip() or line.lstrip().startswith(";"):
                header.append(line)
            else:
                break
        if header:
            parts.append(str(source.relative_to(media)) + "\n" + "\n".join(header))
destination = root / "ArchiveDeskIOS/ThirdParty/CodecNotices.txt"
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text("\n\n".join(parts))
print(f"Generated upstream notices: {destination.stat().st_size} bytes")
