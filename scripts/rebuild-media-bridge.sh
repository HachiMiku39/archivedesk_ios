#!/bin/zsh
# Rebuild the app-owned bridge against the exact cached source-built libraries.
# For a clean checkout use build-media-codecs.sh instead.
set -eu
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
for task_slice in macos-arm64 ios-arm64 ios-simulator-arm64 ios-simulator-x86_64; do
  case "$task_slice" in
    macos-arm64) task_sdk=macosx; task_target=arm64-apple-macosx26.0 ;;
    ios-arm64) task_sdk=iphoneos; task_target=arm64-apple-ios26.0 ;;
    ios-simulator-arm64) task_sdk=iphonesimulator; task_target=arm64-apple-ios26.0-simulator ;;
    ios-simulator-x86_64) task_sdk=iphonesimulator; task_target=x86_64-apple-ios26.0-simulator ;;
  esac
  task_dir="$PWD/work/media-codecs/$task_slice"
  task_prefix="$task_dir/prefix"
  [[ -f "$task_prefix/lib/libavformat.a" ]] || { print -u2 'Missing exact cached build; use build-media-codecs.sh'; exit 1; }
  xcrun --sdk "$task_sdk" clang -target "$task_target" -isysroot "$(xcrun --sdk "$task_sdk" --show-sdk-path)" \
    -O2 -Wall -Wextra -Werror -fPIC -I "$task_prefix/include" -I Vendor/MediaSupport \
    -c Vendor/MediaSupport/ArchiveMedia.c -o "$task_dir/ArchiveMedia.o"
  xcrun libtool -static -o "$task_dir/libArchiveMedia.a" "$task_dir/ArchiveMedia.o" \
    "$task_prefix/lib/libavformat.a" "$task_prefix/lib/libavcodec.a" \
    "$task_prefix/lib/libswscale.a" "$task_prefix/lib/libswresample.a" \
    "$task_prefix/lib/libavutil.a" "$task_prefix/lib/libdav1d.a"
done
xcrun lipo -create work/media-codecs/ios-simulator-arm64/libArchiveMedia.a \
  work/media-codecs/ios-simulator-x86_64/libArchiveMedia.a -output work/media-codecs/ios-simulator/libArchiveMedia.a
for task_slice in macos-arm64 ios-arm64 ios-simulator; do
  task_destination="$task_slice"
  [[ "$task_slice" != ios-simulator ]] || task_destination=ios-arm64_x86_64-simulator
  cp "work/media-codecs/$task_slice/libArchiveMedia.a" "Vendor/ArchiveMedia.xcframework/$task_destination/"
  cp Vendor/MediaSupport/ArchiveMedia.h "Vendor/ArchiveMedia.xcframework/$task_destination/Headers/"
done
