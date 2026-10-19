# Music tags and embedded artwork — 0.3.3 build 6

Music entries in an archive can display their embedded tags and cover directly
in the existing audio preview. This is a read-only tag viewer, not the Mp3tag
application or a tag editor. No changes are made to the source music/archive.

- FFmpeg's format and selected audio-stream metadata are read after the selected
  entry has completed extraction/decryption and archive integrity checks.
- Common labels: title, artist, album, album artist, track/disc number, date/year,
  genre, composer, comments, lyrics, copyright and encoder. Additional embedded
  fields are shown by their original key. Empty values are omitted; duplicate
  keys use the first nonempty value (container before audio stream).
- MP3 ID3v2, FLAC/Vorbis comments and M4A tags are handled by the existing
  source-built FFmpeg backend; this does not promise every tag revision/format.
- Embedded JPEG/PNG attached pictures are software decoded using FFmpeg. No
  ImageIO, AVAsset metadata reader, system compressed-image decoder, external
  cover URL, sidecar file, network service or music-library permission is used.
- Cover streams are excluded from timed video playback. Missing artwork keeps
  the waveform placeholder; rejected/damaged artwork displays a notice without
  disabling valid audio. A new selection clears the previous cover and tags.
- Audio codec, sample rate, channels and bit rate (when available) are shown.
  Unknown tags remain literal text, never executed or fetched.

## Resource and privacy boundaries

At most 64 tag entries are considered (plus one count-limit probe), with a
127-byte key and 2,048-byte value per entry. Truncated fields/counts are indicated
in the UI. These are display limits; FFmpeg demuxing retains its own metadata.
They are not a new whole-process memory guarantee. Existing file/allocation
limits, cancellation and per-preview memory checks still apply.

Covers must be JPEG/PNG, at most 8 MiB encoded and 8,294,400 decoded input pixels;
RGBA output has a longest edge of 1,280. Cover decoding is serial/off-main-thread,
with one output image retained, and does not consume or seek the audio stream.
If several covers are embedded, the first supported decodable one is used.
Existing encrypted-preview gates, staging cleanup and foreground-only behavior
remain unchanged. No tag/artwork data is logged or persistently cached.

## Reproducible verification

Generate synthetic (non-user) MP3 ID3v2.3/2.4, FLAC, M4A, WAV and edge-case
fixtures using `zsh scripts/make-music-tag-fixtures.sh`. The host FFmpeg CLI is
only a test-data generator, never an app runtime dependency. Fixtures stay under
ignored `work/music-tag-fixtures`, not in the app bundle or release source.

`Tests/MusicTagVerification.c` checks exact multilingual tags, JPEG/PNG covers,
no-cover cases, oversize/damaged cover fallback, metadata bounds, complete PCM
decode, repeat access, cancellation and seeking after cover access. Run
`zsh scripts/verify-music-tags.sh` for both C and Swift model checks.
`testMusicTagsAndArtwork` exercises the
same ZIP through native iOS UI including selection changes and playback/pause.

### 2026-10-19 results

- C backend: eight files passed full PCM decode and seek after metadata/cover
  access (MP3 ID3v2.3/2.4, FLAC, M4A, plain WAV, oversize-pixel FLAC cover,
  invalid JPEG and >8 MiB encoded cover). Separate tag-count/value bounds,
  repeated-cover access and cooperative cancellation checks passed.
- Swift metadata model: exact Unicode, ordering, deduplication, empty state,
  cover access and 64-entry/limited-value display checks passed.
- Existing core suite: 111 checks passed. Two macOS coordinated-file integration
  cases remain explicit skips; these are not passed iOS provider tests.
- One iPad Pro 11-inch (M5), iPadOS 27.2 simulator only: the music UI case passed
  all nine sample selections, including playback/pause and stale-cover clearing,
  with no skips (150.823 seconds). Xcode 27.2 / 27.2 SDK Debug build.
- On that same simulator, using the 27.1 SDK / `DUO_SDK` Debug build: Chinese
  labels with accessibility3 text size and landscape passed (26.413 seconds),
  entire-folder/all/multiple extraction passed (59.161 seconds), and ZIP/TAR
  multi-source creation passed (66.058 seconds). Four distinct native UI cases
  passed in total. The first Chinese automation attempt did not scroll the lazy
  sidebar to the last item; adding the necessary scroll fixed the test.
- Device Release builds succeeded under both the 27.2 SDK and the original 27.1
  SDK. The local IPA uses Xcode 27.1 beta / SDK 27.1 with `DUO_SDK` enabled to
  retain the previous Duo-specific public layout branch, minimum OS 26.0.

Tests exposed and fixed accessibility identifiers being inherited from the
whole tags container and overriding individual field identifiers. Xcode's
simulator accessibility/runtime and post-test diagnostic warnings are not
claimed to be eliminated. Physical-device QA is not implied by simulator
results. The previously published 0.3.2 IPA is unchanged.
This task does not re-test the previous USB/provider or physical-device issues;
their known limitations remain in [PHYSICAL-QA-0.3.2.md](PHYSICAL-QA-0.3.2.md).

## Implementation references

[FFmpeg 9.0 AVStream / attached picture API](https://ffmpeg.org/doxygen/9.0/avformat_8h_source.html)
and [FFmpeg metadata dictionary API](https://ffmpeg.org/doxygen/9.0/group__lavu__dict.html).
FFmpeg/dav1d configurations and licensing requirements remain as documented in
[MEDIA-PREVIEW.md](MEDIA-PREVIEW.md). All three XCFramework slices are rebuilt
when this app-owned bridge API changes; do not mix old libraries/new headers.
