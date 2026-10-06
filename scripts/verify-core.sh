#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
mkdir -p work/bin work/ModuleCache
task_codecs="$PWD/Vendor/ArchiveCodecs.xcframework/macos-arm64"
task_rar="$PWD/Vendor/ArchiveRar.xcframework/macos-arm64"
task_sdk=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
/usr/bin/xcrun swiftc -D DEBUG -parse-as-library -swift-version 6 \
  -target arm64-apple-macosx26.0 -sdk "$task_sdk" \
  -module-cache-path work/ModuleCache \
  -I "$task_codecs/Headers" -L "$task_codecs" -lArchiveCodecs -lz -lbz2 -liconv \
  -I "$PWD/Vendor/RARSupport" -L "$task_rar" -lArchiveRar -lc++ \
  ArchiveDeskIOS/ArchiveModels.swift ArchiveDeskIOS/ArchiveSafety.swift ArchiveDeskIOS/OperationMetrics.swift \
  ArchiveDeskIOS/CRC32.swift ArchiveDeskIOS/ZIPArchive.swift \
  ArchiveDeskIOS/ArchiveContainer.swift ArchiveDeskIOS/MultiFormatArchive.swift ArchiveDeskIOS/RARArchive.swift \
  ArchiveDeskIOS/CoordinatedFileAccess.swift ArchiveDeskIOS/ExtractionDestination.swift ArchiveDeskIOS/ArchivePacking.swift ArchiveDeskIOS/WorkspaceModel.swift \
  ArchiveDeskIOS/DebugArchiveFixture.swift ArchiveDeskIOS/PerformanceModel.swift Tests/CoreVerification.swift \
  -o work/bin/core-verification
work/bin/core-verification
