# Open-source media preview (0.3.2 development)

The decoder is source-built FFmpeg 9.0.2 plus dav1d 1.5.4. No FFmpeg CLI,
AVPlayer, Quick Look, ImageIO, AudioToolbox compressed codec or VideoToolbox
decoder is used. CoreGraphics displays decoded RGBA pixels and AVAudioEngine
renders decoded Float32 PCM; those system output APIs are not decoders.
Text uses Swift standard-library UTF-8 and BOM-marked UTF-16 decoding.

0.3.3 adds read-only music tags and embedded JPEG/PNG album covers using this
same backend, with independent cover decoding and bounded metadata display.
See [music tag scope, limits and tests](MUSIC-TAGS-0.3.3.md).

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
RGBA output longest side 480/640 for inline timed video (1024/1280 for still
images; independent music artwork remains capped at 1280), and stereo 48 kHz
Float32 output. Since build 8 the PCM
renderer queues at most 32 buffers / 32,768 frames in total; one larger backend
block (at most 65,536 frames) is permitted alone. Small packets pre-roll 4,096
frames before starting; EOF starts shorter clips. Decoded video look-ahead is
limited to 12 surfaces and 12 MiB, whichever limit is reached first.
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

### Build 8 playback scheduling candidate

Build 7 stutter affects audio as well as video (user-confirmed). The prior
serial consumer waited for each video deadline before reading subsequent audio;
four AAC 1,024-sample buffers at 48 kHz provided only about 85 ms of PCM headroom.
This is a code-identified scheduling weakness, not a measured sole root cause.

Build 8 separates bounded video look-ahead from a presentation tick (10 ms in
build 8, 12 ms in build 9).
Audio scheduling can proceed without waiting for every displayed video frame.
The clock uses `AVAudioPlayerNode.playerTime(forNodeTime:)` while queued PCM
is rendering; its last reading anchors the monotonic fallback for video-only
or drained audio. UI position updates are throttled to about 10 Hz. Pause,
seek, generation change, background/reset and failure preserve cancellation
and stop output; seek, reset and failure clear stale queues. Pausing retains
only the bounded pre-roll for resume. EOF waits for queued video and PCM to drain.
Compressed decoding remains source-built FFmpeg/dav1d; Apple's engine only
renders decoded PCM. No thread-count or hardware-decoder change was made.

`zsh scripts/verify-media-playback-buffer.sh` passed count/byte limits,
future-frame retention, newest-due selection, queue reset, invalid input,
audio concurrency/backpressure and clock-anchor/fallback checks. The original
private-media UI case passed on the same single iPad simulator in 77.224 seconds
(0 failures/skips). Physical-device smoothness is still under evaluation.
Opt-in `--media-diagnostics` emits only submitted/skipped frame and audio queue
empty-refill counts on completion, not paths, tags, media bytes or passwords.

### Build 7 inline output and encryption regression

The 640-pixel video cap reduces the supplied 16:9 sample's RGBA surface from
1280×720 to 640×360 (75% fewer output bytes per frame). It does not lower the
source frame rate or native-resolution AV1 decode workload, and is not a
claim that physical-device stutter has been eliminated. Artwork is decoded
independently and keeps its previous quality limit.

`zsh scripts/verify-video-preview-limit.sh VIDEO JPEG COVER_FLAC` compares full
1280/640 output decode, frame counts, audio sample counts, timestamps, seek,
invalid limits, and unchanged still-image/artwork dimensions. On 2026-10-19,
the supplied AV1/AAC file produced identical 2,819 video frames and 4,511,712
PCM frames at both limits. The original JPEG remained 900×900 and the new
embedded FLAC cover remained 700×700.

`zsh scripts/verify-encrypted-media.sh PRIVATE_FIXTURE_FOLDER` verifies five
private media files in both visible-name and encrypted-header RAR5 archives:
missing/wrong-password rejection, failure rollback, SHA-256 identity after
decryption, and post-decryption media/text/tag/artwork decoding. Both cases
passed on 2026-10-19. ZipCrypto and AES-256 ZIP fixtures list encrypted names
but remain unextractable; no plaintext is staged. These are host backend
checks, not a substitute for physical-device UI verification. The RARLAB
trial executable used with user approval to generate private RAR fixtures is
not an app dependency and is never included in source or release artifacts.

Build 7's private-media UI case also passed on the same single iPad Pro
11-inch (M5) / iPadOS 27.2 simulator: JPEG display, FLAC and AV1/AAC
play/pause/seek, and UTF-16 text preview; 1 test, 0 failures/skips,
79.926 seconds, 2026-10-19 20:01:59. This is not a physical playback
smoothness benchmark. The core suite passed 111 checks with the same two
explicit macOS coordinated-file integration skips, and music metadata/artwork
C/Swift regressions passed again.

Physical iPhone Air / iOS 27.2, signed 0.3.3 build 7:

- Visible-name RAR5 listed names without exposing content; a wrong password
  kept music locked. After successful selected-entry decryption, the supplied
  FLAC displayed its real embedded cover and matching title/artist/album/track;
  play/pause and advancing playback position were observed.
- Header-encrypted RAR5 required a password before listing. Listing did not
  retain the password for content preview: selecting AV1 video prompted again,
  with no thumbnail before decryption. Correct decryption enabled video play.
- UTF-16 text and JPEG entries in that header-encrypted RAR also prompted
  separately, showing no text/thumbnail before decryption and the expected
  multilingual text/image after successful decryption.
- AES-256 ZIP exposed names but no tags/artwork/audio; after password input it
  explicitly reported unsupported encrypted ZIP preview and no content decoded.
- These observations do not establish measured video frame pacing, complete
  audio/video synchronization, prolonged playback stability or external USB
  provider behavior. ZipCrypto's complete entry coverage is a host check.

The user explicitly reported continued AV1 stuttering with build 7 on the
physical phone. The 640-pixel output cap is therefore **not a resolved stutter
fix**. Build 7's wall-clock pacing, late-video dropping and serialized
audio/video delivery required further profiling. This negative result describes
build 7, before the build 8 scheduling change below.

Build 8 follow-up: the user confirmed that both picture and sound were normal
on the same iPhone Air AV1/AAC sample after the scheduling change. Its completed
run reported 2,755 submitted video frames, 64 superseded/dropped surfaces, and
0 empty-audio-queue refills. These are app counters, not display-hardware FPS,
system underrun or general performance guarantees. Music/artwork UI and RAR
password retry/preview/extraction UI also passed on the same iPad simulator
(148.776 and 79.741 seconds). A simulator diagnostics-collection warning about
`simctl` remained after the successful tests; no zero-warning claim is made.

### Build 9 resource tiers

Physical RAM selects a conservative baseline, not an app memory entitlement:

| Device RAM tier | Timed video long edge | Video queue byte ceiling |
| --- | --- | --- |
| Up to 6 GiB | 480 | 6 MiB |
| Up to 8 GiB | 640 | 8 MiB |
| Up to 12 GiB | 640 | 12 MiB |
| Above 12 GiB (16 GiB tier) | 640 | 12 MiB |

Unknown/less RAM uses the 6 GiB profile. At preview start, low-power mode,
serious/critical thermal state or advisory app headroom below 384 MiB also
selects the 480 / 6 MiB profile. Still-image output becomes 1024 long edge in
that profile; music artwork keeps its independent 1280 ceiling. Audio's proven
sample/buffer limits and pre-roll are unchanged in every tier. The policy does
not assume that RAM size predicts CPU/codec speed and does not increase decoder
threads or archive dictionary budgets for larger RAM devices.

The physical-RAM tier is stable; dynamic headroom is not treated as a cached
reservation. Existing live headroom checks, the 192 MiB new-work gate, 64 MiB
stop threshold, system memory-warning cancellation and background cleanup
remain in place. Apple states that app memory headroom can change and is not
the same as device physical RAM: https://developer.apple.com/documentation/os/os_proc_available_memory

Presentation ticks stop entirely while paused/ended; a paused decoder's control
poll slows from 40 to 150 ms. Foreground CPU/RAM task sampling remains 1 Hz
while working/playing, but drops to every 3 seconds while idle. Color space is
reused rather than recreated for every video frame. These are bounded overhead
reductions, not a measured whole-app CPU percentage improvement.

The pure policy/queue suite covers all four tiers and low-power, thermal and
headroom downgrades. The simulator-only Debug flag `--preview-memory-gb=6`
exercises the low-tier media path without needing another simulator; it does
not reproduce a physical 6 GiB device's CPU, memory pressure or jetsam limit.

Build 9 verification on 2026-10-19: the same iPad Pro 11-inch M5 simulator
passed the normal private-media case (82.984 s) and forced 6 GiB case
(74.053 s), with 0 failures/skips. The image accessibility value confirmed
640×360 versus 480×270 timed-video output; the original 900×900 JPEG remained
unchanged in both. Play/pause/seek and FLAC/UTF-16 previews were exercised.
The four-tier unit suite also passed. Four new core checks cover empty/ready/
failed decoder controls and failed EOF-drain cleanup, so a renderer failure
cannot leave a decoder/staged-media task polling indefinitely. The final host
core run passed 118 checks without skips when executed with host coordination
access; this does not verify physical iOS providers or USB behavior.

The final signed build 9 also completed the original AV1/AAC run on iPhone Air:
2,765 submitted video frames + 54 skipped/superseded frames = all 2,819 decoded
frames, 0 empty-audio-queue refills. One in-play UI sample showed 87.8 MB app
footprint and 56% of one CPU core; this is not a peak, controlled comparison,
whole-device CPU reading or a guarantee for other formats/devices. Subjective
build 8 smoothness was user-confirmed. Final build 9 was retested without a
diagnostic restart: the same process remained alive through the original clip,
and the user confirmed normal picture/sound and no exit. Two in-play samples
were 93.9–95 MB and 51–54.3% of one core, not peaks or controlled benchmarks.
The initially reported exit coincided with our deliberate diagnostic-session
restart at 20:44. No matching-time app crash or jetsam report was found; an
earlier disk-write resource warning explicitly recorded no termination action.
This does not exclude every possible crash or validate other devices.

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
