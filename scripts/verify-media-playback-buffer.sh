#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
mkdir -p work/bin work/ModuleCache
xcrun swiftc -parse-as-library -swift-version 6 -target arm64-apple-macosx26.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" -module-cache-path work/ModuleCache \
  -I Vendor/MediaSupport -L Vendor/ArchiveMedia.xcframework/macos-arm64 -lArchiveMedia -lz -liconv \
  ArchiveDeskIOS/ArchiveMediaDecoder.swift ArchiveDeskIOS/MediaPlaybackBuffer.swift \
  Tests/MediaPlaybackBufferVerification.swift -o work/bin/media-playback-buffer-verification
work/bin/media-playback-buffer-verification
