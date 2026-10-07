# Open-source media preview (0.3.2 development)

The decoder is source-built FFmpeg 9.0.2 plus dav1d 1.5.4. No FFmpeg CLI,
AVPlayer, Quick Look, ImageIO, AudioToolbox compressed codec or VideoToolbox
decoder is used. CoreGraphics displays decoded RGBA pixels and AVAudioEngine
renders decoded Float32 PCM; those system output APIs are not decoders.
Text uses Swift standard-library UTF-8 and BOM-marked UTF-16 decoding.

## Pipeline and bounds

Select one entry → require its password when encrypted → extract/decrypt that
entry into task-owned storage → complete archive integrity checks → software
decode. Seeing a filename is not permission to preview its encrypted contents.
Password-protected RAR is supported; encrypted ZIP remains unsupported and is
blocked before staging or decoding, even if a password has been entered.
Passwords remain task-scoped and are not saved or logged.

Only the selected entry is staged, not the entire expanded archive. Source
files up to 512 MiB (images 32 MiB) are eligible. Text is limited to 256 KiB.
Preview stages are deleted on navigation, cancellation, backgrounding or task
completion; the currently open archive's existing immutable snapshot remains.
No preview cache, media fixture or user artwork belongs in a released IPA or
published source package.

Decoder limits: regular local file with no symbolic-link final component,
custom seekable 64 KiB I/O, no network or external media references, at most
8 streams, 8 MiB packets, two decoding threads, 8,294,400 input pixels,
RGBA output longest side 1280, and stereo 48 kHz Float32 output. The PCM
renderer queues at most four buffers, each at most 65,536 frames.
Audio session configuration is performed off the main thread. The iOS 27
async activation API is used when available; iOS 26 uses an off-main-thread
fallback. Cancellation is rechecked before starting PCM output, and stale
generation/seek candidates are discarded instead of attaching to a new preview.
FFmpeg allocations have a 64 MiB per-allocation cap; this is **not a total
process memory guarantee** and does not cover dav1d's allocator. App memory
monitoring and cancellation remain enabled. Physical-device memory pressure,
energy, audio/video synchronization and prolonged playback need further QA.
Software decoding trades hardware efficiency for the requested open-source
decoder requirement. No device-performance benchmark is claimed.

## Configured formats versus verified formats

Configured decoders include AAC, FLAC, MP3, PCM, Vorbis, Opus, JPEG, PNG,
WebP, H.264, HEVC and AV1 (dav1d). Configured demuxers include MP4/MOV,
Matroska/WebM, FLAC, MP3, raw AAC, WAV, Ogg and the three image pipes.
This is not a guarantee that every codec/container combination will play.
HEIC, AVIF, GIF, PDF and Office document rendering are not implemented.
HDR tone mapping and image-orientation metadata are not yet handled.

2026-10-06 host verification uses the newly built open-source libraries:

- User's 1920×1080 10-bit AV1 MP4 with AAC: full decode, seek and cancellation.
- User's stereo 44.1 kHz FLAC: full decode, seek and cancellation.
- User's 900×900 JPEG: decoded RGBA pixels and cancellation.
- User's BOM-marked UTF-16LE log: exact text preview after extraction.
- Actual app ZIP/TAR packing of all four inputs: SHA-256 round-trip matches,
  complete byte progress, and decoding of the extracted selected entries.

Native iPad Pro 11-inch (M5) / iPadOS 27.2 UI verification passed 6/6 with
no skips at 2026-10-06 21:35:47 (349.196 seconds), including the private
JPEG, FLAC, AV1/AAC and UTF-16 fixture. Image display, playback, pause,
seek and navigation were checked; the test does not play each track to its
end. Host full software decoding is a separate test. Physical USB/provider
and device energy/memory-pressure verification remain outstanding.
After moving session activation off the main thread, the same private-media
UI case passed again (1/1, 163.488 seconds, 21:49:38). Session main-thread
activation warnings were absent; an internal QoS/priority-inversion warning
remains and requires physical-device profiling. No zero-warning claim is made.
Private fixtures can be generated with
`scripts/verify-media-packing.sh PRIVATE_OUTPUT VIDEO AUDIO TEXT IMAGE`;
the optional native UI test deliberately skips when that private fixture is
absent. Full sample playback tests are not replaced by a thumbnail-only check.

## Corresponding source and licensing materials

Official source archives, pinned hashes, FFmpeg detached signature and trusted
release key are retained in `Vendor/Sources`. Run
`scripts/verify-media-source.py` with its PGPy dependency to verify the signature.
`scripts/build-media-codecs.sh` builds only static libraries, with GPL,
version3 and nonfree components disabled. dav1d is BSD-2-Clause; FFmpeg's
configured license is LGPL-2.1-or-later. See the complete bundled notices.
No claim of codec patent clearance or App Store approval is made.

Published binary distribution must include corresponding source, recipe,
bridge, matching app object files, the media static library and a usable
relink kit. `relink-ios.sh` accepts replacement media as its third argument.

Sources: [FFmpeg downloads](https://ffmpeg.org/download.html),
[FFmpeg licensing](https://ffmpeg.org/legal.html),
[FFmpeg Darwin builds](https://ffmpeg.org/platform.html),
[dav1d source](https://code.videolan.org/videolan/dav1d).
