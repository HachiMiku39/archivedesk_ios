#!/bin/zsh
# Synthetic, redistributable fixtures; never copy a user's music or artwork.
# The host ffmpeg CLI only generates tests, and is never shipped in the app.
set -eu
cd "${0:A:h:h}"
task_output="$PWD/work/music-tag-fixtures"
mkdir -p "$task_output"
task_ffmpeg="${FFMPEG:-/opt/homebrew/bin/ffmpeg}"
"$task_ffmpeg" -hide_banner -loglevel error -y -f lavfi -i 'color=c=0x267c9e:s=480x480' -frames:v 1 "$task_output/cover.jpg"
"$task_ffmpeg" -hide_banner -loglevel error -y -f lavfi -i 'color=c=0x644fc1:s=400x400' -frames:v 1 "$task_output/cover.png"
for task_ext in mp3 flac m4a; do
  task_codec=flac; task_extra=(); task_cover=cover.jpg
  case "$task_ext" in
    mp3) task_codec=libmp3lame; task_extra=(-id3v2_version 3) ;;
    m4a) task_codec=aac; task_cover=cover.png ;;
  esac
  "$task_ffmpeg" -hide_banner -loglevel error -y -f lavfi -i 'sine=frequency=440:duration=12:sample_rate=44100' \
    -i "$task_output/$task_cover" -map 0:a -map 1:v -c:a "$task_codec" -c:v copy -disposition:v attached_pic \
    -metadata title='星のうた · 测试曲' -metadata artist='ArchiveDesk Artist' -metadata album='Preview Test Album' \
    -metadata album_artist='Various Artists' -metadata track='3/12' -metadata disc='1/2' \
    -metadata date=2026 -metadata genre=Test -metadata composer='Open Source Composer' \
    -metadata comment='Synthetic metadata fixture — not user music' "${task_extra[@]}" "$task_output/tagged.$task_ext"
done
"$task_ffmpeg" -hide_banner -loglevel error -y -f lavfi -i 'sine=duration=3:sample_rate=48000' \
  -map_metadata -1 -fflags +bitexact -flags:a +bitexact -c:a pcm_s16le "$task_output/plain.wav"
"$task_ffmpeg" -hide_banner -loglevel error -y -f lavfi -i 'color=s=5000x2000:c=blue' -frames:v 1 "$task_output/oversized.jpg"
"$task_ffmpeg" -hide_banner -loglevel error -y -i "$task_output/plain.wav" -i "$task_output/oversized.jpg" \
  -map 0:a -map 1:v -c:a flac -c:v copy -disposition:v attached_pic -metadata title='Oversized artwork' "$task_output/oversized.flac"
# Verify both widely used ID3v2 revisions.
"$task_ffmpeg" -hide_banner -loglevel error -y -i "$task_output/tagged.mp3" -c copy -id3v2_version 4 "$task_output/id3v24.mp3"
python3 scripts/make-music-edge-fixtures.py
(cd "$task_output"; zip -q -j -FS MusicTags.zip tagged.mp3 tagged.flac tagged.m4a plain.wav oversized.flac id3v24.mp3 broken-cover.mp3 large-cover.mp3 long-tags.mp3)
print "$task_output/MusicTags.zip"
