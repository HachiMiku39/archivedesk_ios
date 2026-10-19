#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
mkdir -p work/bin work/ModuleCache
task_media="$PWD/Vendor/ArchiveMedia.xcframework/macos-arm64"
xcrun clang -Wall -Wextra -Werror Tests/MusicTagVerification.c -I Vendor/MediaSupport \
  -L "$task_media" -lArchiveMedia -lz -liconv -o work/bin/music-tag-verification
work/bin/music-tag-verification "$PWD/work/music-tag-fixtures"
xcrun swiftc -parse-as-library -swift-version 6 -target arm64-apple-macosx26.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" -module-cache-path work/ModuleCache \
  -I Vendor/MediaSupport -L "$task_media" -lArchiveMedia -lz -liconv \
  ArchiveDeskIOS/ArchiveMediaDecoder.swift Tests/MusicMetadataVerification.swift \
  -o work/bin/music-metadata-verification
work/bin/music-metadata-verification "$PWD/work/music-tag-fixtures"
