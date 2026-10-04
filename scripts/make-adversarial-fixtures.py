"""Generate deterministic hostile TAR headers for decoder safety regressions."""
import io
import lzma
import tarfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent / "work/format-fixtures"
# Independent standard-library generator for the legacy LZMA-alone container.
payload = (root / "input/Notes.md").read_bytes()
(root / "Notes.md.lzma").write_bytes(lzma.compress(payload, format=lzma.FORMAT_ALONE, filters=[{"id": lzma.FILTER_LZMA1, "dict_size": 1 << 20}]))
for kind, names in {"traversal": ["./../escape.txt"], "absolute": ["/escape.txt"], "case-alias": ["A/x.txt", "a/y.txt"], "unicode-alias": ["é.txt", "e\u0301.txt"], "prefix-conflict": ["A", "A/x.txt"], "current-dir": ["./Notes.md"]}.items():
    with tarfile.open(root / (kind + ".tar"), "w", format=tarfile.USTAR_FORMAT) as archive:
        for name in names:
            payload = b"safe test bytes\n"
            header = tarfile.TarInfo(name)
            header.size = len(payload)
            archive.addfile(header, io.BytesIO(payload))
for kind, filetype in [("symlink", tarfile.SYMTYPE), ("hardlink", tarfile.LNKTYPE), ("fifo", tarfile.FIFOTYPE)]:
    with tarfile.open(root / (kind + ".tar"), "w") as archive:
        header = tarfile.TarInfo("unsafe.txt")
        header.type = filetype
        header.linkname = "../escape"
        archive.addfile(header)
