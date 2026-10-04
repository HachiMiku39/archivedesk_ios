# iOS archive engine selection

## Decision

The Mac 7zz subprocess is not ported into iOS. The app statically links its own libarchive 3.8.9 and liblzma 5.8.4 builds, using public system zlib, bzip2 and iconv. Registered readers/filters run in process without external-program fallback. Apple private libarchive/liblzma stubs are not linked.

- [PLzmaSDK](https://github.com/OlehKulykov/PLzmaSDK): iOS-capable LZMA SDK wrapper, evaluated but not shipped; suitable for focused 7z work.
- [Official LZMA SDK](https://www.7-zip.org/sdk.html): useful 7z/LZMA/XZ subset, not the complete desktop format set.
- [libarchive formats](https://github.com/libarchive/libarchive/wiki/LibarchiveFormats): broader read coverage motivated selection; compiled dependencies and fixtures determine actual app capabilities.

Full 7-Zip's [license mix](https://www.7-zip.org/faq.html) differs from the SDK. Open-source licensing is not App Store/legal approval. [Apple review rules](https://developer.apple.com/app-store/review/guidelines/) still apply.

## Pinned sources

- [libarchive 3.8.9 release](https://github.com/libarchive/libarchive/releases/tag/v3.8.9): SHA-256 `888c934f9d95648ecb9163dc8e23ab80a476ecb81a8f1154704a227b5b676dde`.
- [XZ 5.8.4 release](https://github.com/tukaani-project/xz/releases/tag/v5.8.4): SHA-256 `0014c7886930454fe8bd4228665b51af55eeae560ea135c9c4cd33f55b2591d9`.

Hashes matched official release asset digests. Pristine tarballs are in Vendor/Sources. The script uses explicit SDK/sysroot, single-threaded XZ and vendor allocator interposition, with pkg-config disabled to avoid Homebrew leakage. XCFramework: arm64 iOS, arm64+x86_64 Simulator and arm64 macOS host-test slices; target 26.0. Mac slice is test-only.

`generate-codec-notices.py` reproduces upstream COPYING and individual libarchive C/header notices in Information → Open-source notices. [libarchive per-file terms](https://github.com/libarchive/libarchive/blob/master/COPYING) control; [liblzma is 0BSD](https://tukaani.org/xz/). Recheck licenses and security releases before public distribution.

## Safety / limits

Readers stay on one synchronous thread through deinit. Vendor allocations are capped at 128 MiB each and 256 MiB live per thread; ENOMEM is returned beyond limits. This is not total RSS or a system-library allocation cap. A throwing Swift initializer is cleaned only by deinit after all properties are initialized; manual catch cleanup was removed after Duo cancellation exposed a double-free.

Listing validates paths/types/collisions and budgets. Leading ./ is stripped only as a harmless convention; .. is never resolved. Archive root records are skipped only for real non-link directories. Output is streamed to fresh owned staging and published by same-volume rename. ZIP retains independent CRC and strict header validation. TAR/ISO do not magically gain checksums.

Cancellation is checked between headers/chunks; solid-stream skips can delay it. Selected-file extraction may re-decode earlier blocks. No hard CPU timeout or optimal solid-archive performance is claimed. ZIP/7z encryption, split volumes, Zstd/LZ4 and physical-drive/memory-pressure tests remain pending.

## Source-built RAR and archive creation

RAR4/RAR5 now use the source-built 7-Zip 26.03 read-only bridge, with password,
solid and encrypted-header fixture coverage. ZIP/TAR creation uses libarchive's
Deflate ZIP and restricted PAX TAR writers. Multi-source inputs are coordinated
private snapshots; output uses the existing destination policy, a fresh staging
directory and same-volume publication. See [RAR-LICENSE-AND-RELINK.md](RAR-LICENSE-AND-RELINK.md)
for source hashes, modifications and the required binary relink-kit checklist.
The bounded allocator is not an app-wide or C++ new memory cap.

## Unicode names

Native readers use a thread-local UTF-8 C locale while converting archive names, restoring the prior locale after cleanup. The app's global locale is unchanged. This fixes the actual Chinese/Japanese 7z filename fixture failure under the default C locale. The helper uses public Darwin newlocale/uselocale APIs; nested readers restore their parent locale.

Deflate streams use ZIP's CP437 default for names without a UTF-8 flag, matching the strict index parser rather than guessing the current locale. Explicit UTF-8 flags and Unicode extras retain the native ZIP decoder's handling. The CP437 accented-name fixture verifies actual method-8 preview/output bytes.

## Icon

The public iOS build uses an original geometric archive-box icon rendered by scripts/render-app-icon.swift. It is a 1024×1024 opaque RGB PNG with no third-party character artwork. The previously tested Mac character icon is not included in the public repository or IPA; the Mac project/app were not modified.
