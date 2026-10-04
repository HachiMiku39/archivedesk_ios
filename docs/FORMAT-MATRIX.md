# Format capability matrix

Updated 2026-10-04. Yes means an integrated reader with sample evidence, not every codec/variant supported. All formats share the same safe destination policy.

| Format | Browse | Extract | Create | Encryption | Current evidence |
|---|---:|---:|---:|---:|---|
| ZIP (stored) | Yes | Yes | No | No | Host fixtures and streaming CRC |
| ZIP (deflate) | Yes | Yes | No | No | Actual method-8 archive preview/output bytes verified; only methods 0/8 admitted |
| ZIP64 | Yes | Stored/Deflate path | No | No | Tiny EOCD/extra-field vectors; >4 GiB physical-device fixtures pending |
| IPA | As ZIP only | Same as ZIP | No | No | Dedicated inspector not yet ported |
| APK | As ZIP only | Same as ZIP | No | No | Dedicated inspector not yet ported |
| RAR (v3/v4 family) | Yes | Yes | No | No | Upstream binary-data fixture, two independent CRC vectors |
| RAR5 | Yes | Yes | No | No | Compressed and solid multi-file vectors verified byte-for-byte |
| 7z LZMA/LZMA2 | Yes | Yes | No | No | Actual 7-Zip-generated samples, including LZMA2 solid multi-file archive |
| TAR / TAR.gz / TAR.bz2 / TAR.xz | Yes | Yes | No | N/A | Host bytes; leading ./ convention and unsafe path/link rejection |
| gzip/bzip2/XZ streams | Yes | Yes | No | N/A | Host preview/output-byte checks; listing scans raw output to determine length |
| Raw LZMA stream | Yes | Yes | No | N/A | Independent LZMA-alone sample preview/output bytes verified |
| Zstd/LZ4 | No | No | No | N/A | Not compiled or registered |
| ISO9660 | Yes | Yes | No | N/A | Two upstream sample files verified as hello + newline |

RAR creation, recovery records/volumes, archive editing, DRM bypass, package execution, GPU decompression, and unlimited background execution are out of scope for 1.0.

Unsupported codecs, passwords and split-volume workflows are not promised. Archive links/special files and case/Unicode collisions are rejected even if desktop tools accept them. TAR/ISO do not gain a checksum; length/safety checks and only format-supplied integrity checks apply.

Host format verification covers 15 normal archives/streams, allocation cap, 9 malicious/link archives, 3 corruption/rollback cases, 3 invalid inputs and cancelled initializer cleanup. Core regression has 55 passes and two explicit desktop coordination skips. Native UI evidence is recorded separately in the latest output report; host tests do not verify folding, Files providers or physical-device performance.
