# RAR source backend and relinking

7-Zip 26.03 is compiled from source, not from a RARLAB binary or desktop CLI.
Only RAR readers/decoders, a read-only UDF image handler and their dependencies are built. RAR writing,
encryption creation, volume creation and recovery creation are not exposed.

Upstream source: https://github.com/ip7z/7zip/releases/tag/26.03

Pristine archive: `Vendor/Sources/7z2603-src.tar.xz`

SHA-256: `9cbde5099c6deb73691b0579063da5827522ccbbcba3f0020fd04e8c8c16c0d4`

## Licenses

The bridge in `Vendor/RARSupport` is LGPL-2.1-or-later. Upstream 7-Zip has
LGPL-2.1-or-later, BSD/public-domain components, and an additional unRAR
restriction for RAR-related code. Do not use that code to develop a RAR-compatible
archiver. The complete upstream License.txt, copying.txt and unRarLicense.txt are
retained verbatim in the app's `ThirdParty/CodecNotices.txt` and pristine archive.

Authoritative texts: https://github.com/ip7z/7zip/blob/main/DOC/License.txt
and https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html

## Reproducible changes and build

`zsh scripts/build-rar-codecs.sh` extracts the checksum-pinned source and applies
these reproducible mechanical changes; the script is the patch recipe:

- Bound RAR4/RAR5 item arrays at 100,000 entries.
- Bound UDF items/files/references to 100,000, directory recursion to 128,
  extents to 262,144, and aggregate filename/inline-data storage to 32 MiB each.
  Directory/metadata table buffers are limited to 1 MiB and logical blocks to
  64 KiB; regular file payloads are streamed and may exceed 4 GiB.
  These are explicit metadata bounds because the C allocator does not cover C++ new.
- Wipe temporary BSTR data before freeing it.
- Remove the upstream process-global RAR5 password/derived-key cache; task-owned
  decoders derive their own keys. This also avoids sharing that cache across workers.
- Select upstream's offset-alignment allocator branch, so aligned allocations
  and frees both use ArchiveDesk's bounded allocator. Do not combine native
  posix_memalign with the interposed free function.

The modified sources remain in `work/rar-sources`. All compiled objects remain
in `work/rar-codecs/<slice>/objects`. The source-built XCFramework contains iOS
arm64, Simulator arm64/x86_64 and macOS arm64 host-test libraries. The module map
is imported directly from `Vendor/RARSupport` to avoid flat XCFramework header
copy collisions. All readers run synchronously on one worker thread.

The shim also initializes hash/CRC tables explicitly, limits RAR5 dictionary
memory to 128 MiB, rejects volume/error/warning flags and unsafe entry types,
and verifies native extraction status and the expected output length. C allocator
limits do not cover C++ new allocations or the whole app's resident memory.

## Corresponding binary release and relink kit

Release `v0.3.0-beta.1` distributes the unsigned device IPA alongside
`ArchiveDesk-0.3.0-source.tar.gz` and `ArchiveDesk-0.3.0-relink-kit.tar.gz`.
The old v0.1.0-beta.1 IPA predates this backend and remains unchanged.

The matching kit includes the exact arm64 Release application objects in original
link order, both static libraries, the unsigned app resources, full notices,
the modified upstream files (including UdfIn.cpp in UDF-enabled releases), checksums and a tested portable link script.
The source package includes all pristine dependency archives, bridge/allocator
source and checksum-pinned modification/build recipes. No Apple SDK, signing
certificate, provisioning profile or credentials are included.

Extract the source archive into the kit's `source/` directory as described in the
kit README. Use Xcode 27.1 beta (27A9269), iPhoneOS 27.1 SDK (24A94403), target
arm64-apple-ios26.0 and Release objects; rebuild the RAR library with
`RAR_SLICES=ios-arm64 zsh scripts/build-rar-codecs.sh` in the source directory.
Run the kit's `relink.sh` with the replacement static library, then re-sign with
your own valid Apple certificate and provisioning profile before installation.
The script also accepts a replacement ArchiveCodecs library. Its README explains
the build flags, link command differences and checksums.

Permission is granted to use and copy the distributed ArchiveDesk application
object files and resources to relink this application with modified versions of
its LGPL libraries for your own use, and to perform reverse engineering needed
to debug those library modifications. No ArchiveDesk distribution term prohibits
those activities. All applicable third-party permissions remain intact. This
limited permission does not grant a blanket open-source license to the app's own
code or unrestricted redistribution of modified app binaries. App Store
compatibility and unqualified legal compliance are not asserted here.

## Tested boundaries

Host tests cover RAR4 and RAR5 data encryption, encrypted filenames, solid
encryption and solid+encrypted filenames (8 upstream libarchive fixtures), correct
and incorrect passwords, output bytes, rollback, and bounded-allocation cleanup.
Separate passwords within one non-solid archive are tested. These are sample
results, not a promise that every RAR variant is supported. Multi-volume RAR,
self-extracting executables and recovery operations remain unsupported.

Password strings are passed only to the active operation; no password is stored
in archive metadata, settings, history or logging. Temporary bridge password
buffers are wiped. Swift/OS temporary copies are not claimed to be forensically
erasable. Selected solid entries may require re-decoding preceding blocks, and
native key derivation can delay cancellation. No hard CPU deadline is claimed.
