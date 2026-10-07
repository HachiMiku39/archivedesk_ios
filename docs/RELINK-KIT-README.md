# ArchiveDesk @VERSION@ — corresponding device relink kit

This kit matches ArchiveDesk-@VERSION@-unsigned.ipa (build @BUILD@),
SHA-256 `@IPA_SHA@`. It contains the exact arm64 Release application objects
in original link order, matching ArchiveRar/ArchiveCodecs/ArchiveMedia static libraries and
unsigned app resources without the executable. No Apple SDK, credentials,
certificates or provisioning profiles are included.

Original toolchain: Xcode 27.1 beta 27A9269, iPhoneOS 27.1 SDK 24A94403,
Swift 6.4, target arm64-apple-ios26.0, Release Swift -O. Use that SDK to
preserve the Duo-specific public APIs. A newer SDK compiles the project's
standard layout branch instead; it is not the identical original build.

`CodecNotices.txt` retains full third-party terms. `modified-rar-sources.tar.gz`
contains all six modified upstream files, including the UDF metadata limits in
`UdfIn.cpp`. The complete corresponding source,
pristine dependency archives, bridges and build recipes are provided separately
as `ArchiveDesk-@VERSION@-source.tar.gz` in the same Release. See that source's
`docs/RAR-LICENSE-AND-RELINK.md` for modifications and limitations.

## Rebuild and relink

```sh
shasum -a 256 -c SHA256SUMS
mkdir source
tar -xzf /path/to/ArchiveDesk-@VERSION@-source.tar.gz -C source --strip-components=1
export DEVELOPER_DIR=/Applications/Xcode-27.1-beta.app/Contents/Developer
cd source
# Creates work/rar-sources and applies checksum-pinned reproducible modifications.
RAR_SLICES=ios-arm64 zsh scripts/build-rar-codecs.sh
# Edit affected library sources in work/rar-sources and/or Vendor/RARSupport.
RAR_SLICES=ios-arm64 zsh scripts/build-rar-codecs.sh
cd ..
zsh relink.sh "$PWD/source/work/rar-codecs/ios-arm64/libArchiveRar.a"
```

The mechanical modifications are idempotent; change those recipes as well if
altering their affected source regions. To modify ArchiveCodecs, back up its
XCFramework, edit its sources/build recipe and rebuild with `scripts/build-codecs.sh`
in a clean build directory. Pass the replacement library as relink.sh's second
argument. Respect all licenses, including the unRAR restriction; no RAR writer
or closed-source RARLAB CLI is included.

ArchiveMedia contains source-built FFmpeg 9.0.2 (LGPL-2.1-or-later configuration)
and dav1d 1.5.4 (BSD-2-Clause), with GPL/version3/nonfree components disabled.
For a modified media library, unpack the pristine pinned archives into
`work/media-sources`, edit those sources or `Vendor/MediaSupport`, and run
`MEDIA_SLICES=ios-arm64 zsh scripts/build-media-codecs.sh`. Back up the existing
media XCFramework first, as the build recipe refuses to replace it. Pass the
resulting `work/media-codecs/ios-arm64/libArchiveMedia.a` as relink.sh's third
argument (first and second arguments may be the kit's original libraries).
The source recipe disables compressed-system-codec and network backends;
Apple audio output renders only already-decoded PCM. See the source's
`docs/MEDIA-PREVIEW.md` for actual support and bounds.

The link script retains target, SDK, object/library order, Swift runtime paths,
system libraries and dead-strip flags, but omits diagnostic-only absolute build
paths and optional Swift debugging AST. Relinking is operational, not promised
byte-identical reproduction. It generates a new `relinked.XXXXXX/` directory.
Installation requires your own valid Apple certificate/profile and appropriate
bundle identifier/entitlements. No signing bypass or App Store approval is implied.

## Limited application-object permission

Permission is granted to use and copy these ArchiveDesk application objects and
resources to relink this application with modified LGPL libraries for your own
use, and to reverse engineer as needed to debug those library modifications.
No application distribution term prohibits those activities. Applicable
third-party license permissions remain intact. This is not a blanket open-source
license for the app's own code or unrestricted redistribution permission for
modified binaries. The RAR code must not be used to develop a RAR-compatible archiver.
The app has no anti-tamper check rejecting modified libraries. Apple signing rules
still apply, and physical-device installation remains unverified.
