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
parts.append("7-Zip 26.03 source RAR decoder: https://github.com/ip7z/7zip\nArchiveDesk RAR bridge: LGPL-2.1-or-later. RAR creation is not provided. See docs/RAR-LICENSE-AND-RELINK.md for modifications and relinking requirements.")
for name in ["License.txt", "copying.txt", "unRarLicense.txt"]:
    parts.append("7-Zip/DOC/" + name + "\n\n" + (rar / "DOC" / name).read_text())
destination = root / "ArchiveDeskIOS/ThirdParty/CodecNotices.txt"
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text("\n\n".join(parts))
print(f"Generated upstream notices: {destination.stat().st_size} bytes")
