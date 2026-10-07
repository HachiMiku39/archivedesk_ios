#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.1-beta.app/Contents/Developer}"
mkdir -p work/bin work/ModuleCache
task_codecs="$PWD/Vendor/ArchiveCodecs.xcframework/macos-arm64"
task_rar="$PWD/Vendor/ArchiveRar.xcframework/macos-arm64"
task_media="$PWD/Vendor/ArchiveMedia.xcframework/macos-arm64"
task_sdk=$(xcrun --sdk macosx --show-sdk-path)
xcrun swiftc -parse-as-library -swift-version 6 -target arm64-apple-macosx26.0 -sdk "$task_sdk" \
  -module-cache-path work/ModuleCache \
  -I "$task_codecs/Headers" -L "$task_codecs" -lArchiveCodecs -lz -lbz2 -liconv \
  -I "$PWD/Vendor/RARSupport" -L "$task_rar" -lArchiveRar -lc++ \
  -I "$PWD/Vendor/MediaSupport" -L "$task_media" -lArchiveMedia \
  ArchiveDeskIOS/ArchiveModels.swift ArchiveDeskIOS/ArchiveSafety.swift ArchiveDeskIOS/OperationMetrics.swift \
  ArchiveDeskIOS/CRC32.swift ArchiveDeskIOS/ZIPArchive.swift ArchiveDeskIOS/ArchiveContainer.swift \
  ArchiveDeskIOS/MultiFormatArchive.swift ArchiveDeskIOS/RARArchive.swift ArchiveDeskIOS/CoordinatedFileAccess.swift \
  ArchiveDeskIOS/ExtractionDestination.swift ArchiveDeskIOS/ArchivePacking.swift \
  ArchiveDeskIOS/ArchiveMediaDecoder.swift Tests/MediaPackingVerification.swift -o work/bin/media-packing-verification
work/bin/media-packing-verification "$@"
