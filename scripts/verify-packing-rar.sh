#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.1-beta.app/Contents/Developer}"
mkdir -p work/bin work/ModuleCache work/rar-fixtures work/codec-sources
[[ -d work/codec-sources/libarchive-3.8.9 ]] || tar -xJf Vendor/Sources/libarchive-3.8.9.tar.xz -C work/codec-sources
for task_version in 4 5; do
  for task_suffix in encrypted encrypted_filenames solid_encrypted solid_encrypted_filenames; do
    task_name="test_read_format_rar${task_version}_${task_suffix}.rar"
    uudecode -o "work/rar-fixtures/$task_name" "work/codec-sources/libarchive-3.8.9/libarchive/test/$task_name.uu"
  done
done
task_codecs="$PWD/Vendor/ArchiveCodecs.xcframework/macos-arm64"
task_rar="$PWD/Vendor/ArchiveRar.xcframework/macos-arm64"
xcrun swiftc -parse-as-library -swift-version 6 \
  -target arm64-apple-macosx26.0 -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path work/ModuleCache -I "$task_codecs/Headers" -L "$task_codecs" \
  -I "$PWD/Vendor/RARSupport" -L "$task_rar" -lArchiveRar -lc++ -lArchiveCodecs -lz -lbz2 -liconv \
  ArchiveDeskIOS/ArchiveModels.swift ArchiveDeskIOS/ArchiveSafety.swift ArchiveDeskIOS/OperationMetrics.swift ArchiveDeskIOS/CRC32.swift \
  ArchiveDeskIOS/ZIPArchive.swift ArchiveDeskIOS/ArchiveContainer.swift ArchiveDeskIOS/MultiFormatArchive.swift \
  ArchiveDeskIOS/CoordinatedFileAccess.swift ArchiveDeskIOS/ExtractionDestination.swift \
  ArchiveDeskIOS/ArchivePacking.swift ArchiveDeskIOS/RARArchive.swift Tests/PackingRARVerification.swift \
  -o work/bin/packing-rar-verification
work/bin/packing-rar-verification
