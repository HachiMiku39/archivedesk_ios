#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.1-beta.app/Contents/Developer}"
task_root="$PWD"
task_source="$PWD/work/rar-sources"
mkdir -p "$task_source" Vendor/Sources
[[ -f "$task_source/7z2603-src.tar.xz" ]] || cp Vendor/Sources/7z2603-src.tar.xz "$task_source/"
[[ "$(shasum -a 256 "$task_source/7z2603-src.tar.xz" | cut -d ' ' -f 1)" == 9cbde5099c6deb73691b0579063da5827522ccbbcba3f0020fd04e8c8c16c0d4 ]] || exit 1
cp "$task_source/7z2603-src.tar.xz" Vendor/Sources/
[[ -d "$task_source/CPP" ]] || tar -xJf "$task_source/7z2603-src.tar.xz" -C "$task_source"
# Mechanical, reproducible safety changes to upstream LGPL files. Originals
# remain in the checksum-pinned tarball; modified sources stay available here.
perl -0pi -e 's/(?<!100000\) return E_OUTOFMEMORY;\n)      _items\.Add\(item\);/      if (_items.Size() >= 100000) return E_OUTOFMEMORY;\n      _items.Add(item);/g' "$task_source/CPP/7zip/Archive/Rar/Rar5Handler.cpp"
perl -0pi -e 's/(?<!100000\) return E_OUTOFMEMORY;\n)        _items\.Add\(item\);/        if (_items.Size() >= 100000) return E_OUTOFMEMORY;\n        _items.Add(item);/g' "$task_source/CPP/7zip/Archive/Rar/RarHandler.cpp"
perl -0pi -e 's/if \(bstr\)\r?\n    FreeForBSTR/if (bstr)\n  {\n    volatile Byte *wipe = (volatile Byte *)bstr;\n    const UINT size = *((CBstrSizeType *)(void *)bstr - 1);\n    for (UINT i = 0; i < size; ++i) wipe[i] = 0;\n    FreeForBSTR/; s/FreeForBSTR\(\(CBstrSizeType \*\)\(void \*\)bstr - 1\);\r?\n}/FreeForBSTR((CBstrSizeType *)(void *)bstr - 1);\n  }\n}/' "$task_source/CPP/Common/MyWindows.cpp"
# Use upstream's offset-alignment branch: posix_memalign bypasses our bounded
# allocator, so its pointer must never reach the interposed free function.
perl -0pi -e 's/^  #define USE_posix_memalign\r?$/  \/\* ArchiveDesk: bounded allocator uses offset alignment. \*\//mg' "$task_source/C/Alloc.c"
# Upstream RAR5 caches both the password and derived keys globally. Remove both
# cache lookup and population: keys may live only inside a task-owned decoder.
perl -0pi -e 's/static CKey g_Key;.*?(?=bool CDecoder::CalcKey_and_CheckPassword)/\/\/ ArchiveDesk: no process-global password or key cache.\n/s; s/\{\r?\n      MT_LOCK\r?\n      if \(!g_Key\._needCalc && IsKeyEqualTo\(g_Key\)\)\r?\n      \{\r?\n        CopyCalcedKeysFrom\(g_Key\);\r?\n        _needCalc = false;\r?\n      \}\r?\n    \}/\/\* ArchiveDesk: derive only within this task-owned decoder. \*\//; s/\{\r?\n        MT_LOCK\r?\n        g_Key = \*this;\r?\n      \}/\/\* ArchiveDesk: never retain keys across tasks. \*\//' "$task_source/CPP/7zip/Crypto/Rar5Aes.cpp"
! rg -q 'g_Key|MT_LOCK' "$task_source/CPP/7zip/Crypto/Rar5Aes.cpp"
# ArchiveDesk UDF metadata budgets. C++ allocations are not covered by the C
# allocator, so bound upstream vectors, recursion and inline data explicitly.
perl -0pi -e 's/kNumRecursionLevelsMax = [^\n]+/kNumRecursionLevelsMax = 128; \/\/ ArchiveDesk safety budget/; s/kNumItemsMax = [^\n]+/kNumItemsMax = 100000; \/\/ ArchiveDesk safety budget/; s/kNumFilesMax = [^\n]+/kNumFilesMax = 100000; \/\/ ArchiveDesk safety budget/; s/kNumRefsMax = [^\n]+/kNumRefsMax = 100000; \/\/ ArchiveDesk safety budget/; s/kNumExtentsMax = [^\n]+/kNumExtentsMax = 262144; \/\/ ArchiveDesk safety budget/; s/kFileNameLengthTotalMax = [^\n]+/kFileNameLengthTotalMax = 32 * 1024 * 1024; \/\/ ArchiveDesk safety budget/; s/kInlineExtentsSizeMax = [^\n]+/kInlineExtentsSizeMax = 32 * 1024 * 1024; \/\/ ArchiveDesk safety budget/' "$task_source/CPP/7zip/Archive/Udf/UdfIn.cpp"
# Directory/metadata tables are not regular payloads. Bound nested buffers;
# multi-gigabyte files such as install.wim still stream through callbacks.
perl -0pi -e 's/if \(item\.Size >= \(UInt32\)1 << 30\)/if (item.Size > 1024 * 1024)/; s/vol\.BlockSize > \(\(UInt32\)1 << 30\)/vol.BlockSize > 65536/' "$task_source/CPP/7zip/Archive/Udf/UdfIn.cpp"
task_cpp=(
  CPP/Common/CRC.cpp CPP/Common/IntToString.cpp CPP/Common/StringToInt.cpp CPP/Common/MyString.cpp CPP/Common/MyVector.cpp
  CPP/Common/StringConvert.cpp CPP/Common/UTFConvert.cpp CPP/Common/MyWindows.cpp CPP/Common/MyMap.cpp
  CPP/Common/Sha1Prepare.cpp CPP/Common/Sha256Prepare.cpp
  CPP/Windows/PropVariant.cpp CPP/Windows/PropVariantUtils.cpp CPP/Windows/PropVariantConv.cpp
  CPP/Windows/TimeUtils.cpp CPP/Windows/System.cpp CPP/Windows/Synchronization.cpp
  CPP/7zip/Common/CreateCoder.cpp CPP/7zip/Common/FilterCoder.cpp CPP/7zip/Common/InBuffer.cpp
  CPP/7zip/Common/OutBuffer.cpp CPP/7zip/Common/LimitedStreams.cpp CPP/7zip/Common/MethodId.cpp
  CPP/7zip/Common/MethodProps.cpp CPP/7zip/Common/ProgressUtils.cpp CPP/7zip/Common/StreamUtils.cpp
  CPP/7zip/Common/StreamObjects.cpp CPP/7zip/Common/LockedStream.cpp CPP/7zip/Common/PropId.cpp
  CPP/7zip/Archive/Common/FindSignature.cpp CPP/7zip/Archive/Common/ItemNameUtils.cpp
  CPP/7zip/Archive/Common/OutStreamWithCRC.cpp CPP/7zip/Archive/Common/HandlerOut.cpp CPP/7zip/Archive/HandlerCont.cpp
  CPP/7zip/Archive/Rar/RarHandler.cpp CPP/7zip/Archive/Rar/Rar5Handler.cpp
  CPP/7zip/Archive/Udf/UdfHandler.cpp CPP/7zip/Archive/Udf/UdfIn.cpp
  CPP/7zip/Compress/BitlDecoder.cpp CPP/7zip/Compress/LzOutWindow.cpp CPP/7zip/Compress/CopyCoder.cpp
  CPP/7zip/Compress/Rar1Decoder.cpp CPP/7zip/Compress/Rar2Decoder.cpp CPP/7zip/Compress/Rar3Decoder.cpp
  CPP/7zip/Compress/Rar3Vm.cpp CPP/7zip/Compress/Rar5Decoder.cpp
  CPP/7zip/Crypto/MyAes.cpp CPP/7zip/Crypto/HmacSha256.cpp CPP/7zip/Crypto/Rar20Crypto.cpp
  CPP/7zip/Crypto/RarAes.cpp CPP/7zip/Crypto/Rar5Aes.cpp
)
task_c=(C/7zCrc.c C/7zCrcOpt.c C/Alloc.c C/CpuArch.c C/Aes.c C/AesOpt.c
        C/Sha1.c C/Sha1Opt.c C/Sha256.c C/Sha256Opt.c C/Blake2s.c C/Ppmd7.c C/Ppmd7aDec.c C/Bra.c)
task_slices=(macos-arm64 ios-arm64 ios-simulator-arm64 ios-simulator-x86_64)
[[ -z "${RAR_SLICES:-}" ]] || task_slices=(${=RAR_SLICES})
for task_slice in "${task_slices[@]}"; do
  case "$task_slice" in
    macos-arm64) task_sdk=macosx; task_target=arm64-apple-macosx26.0 ;;
    ios-arm64) task_sdk=iphoneos; task_target=arm64-apple-ios26.0 ;;
    ios-simulator-arm64) task_sdk=iphonesimulator; task_target=arm64-apple-ios26.0-simulator ;;
    ios-simulator-x86_64) task_sdk=iphonesimulator; task_target=x86_64-apple-ios26.0-simulator ;;
  esac
  task_dir="$PWD/work/rar-codecs/$task_slice"
  mkdir -p "$task_dir/objects" "$task_dir/Headers"
  task_flags=(-target "$task_target" -isysroot "$(xcrun --sdk "$task_sdk" --show-sdk-path)" -O2 -fPIC -DZ7_ST -DZ7_EXTRACT_ONLY -I "$task_source" -I "$PWD/Vendor/RARSupport")
  task_objects=()
  for task_file in "${task_cpp[@]}" "$task_root/Vendor/RARSupport/ArchiveRar.cpp"; do
    [[ "$task_file" = /* ]] && task_input="$task_file" || task_input="$task_source/$task_file"
    task_object="$task_dir/objects/${task_file:t:r}.o"
    task_objects+=("$task_object")
    xcrun clang++ "${task_flags[@]}" -std=c++17 -c "$task_input" -o "$task_object"
  done
  for task_file in "${task_c[@]}"; do
    task_object="$task_dir/objects/${task_file:t:r}.o"
    task_objects+=("$task_object")
    task_extra=()
    [[ "$task_file" == C/Alloc.c ]] && task_extra=(-include "$PWD/Vendor/Support/codec_allocator.h")
    xcrun clang "${task_flags[@]}" "${task_extra[@]}" -c "$task_source/$task_file" -o "$task_object"
  done
  xcrun libtool -static -o "$task_dir/libArchiveRar.a" "${task_objects[@]}"
  cp Vendor/RARSupport/ArchiveRar.h "$task_dir/Headers/"
  # The Swift module map lives in Vendor/RARSupport. Multiple library-style
  # XCFrameworks otherwise copy a flat include/module.modulemap to one path.
  print "Built RAR $task_slice"
done
if [[ -z "${RAR_SLICES:-}" ]]; then
  mkdir -p work/rar-codecs/ios-simulator-universal
  xcrun lipo -create work/rar-codecs/ios-simulator-arm64/libArchiveRar.a work/rar-codecs/ios-simulator-x86_64/libArchiveRar.a -output work/rar-codecs/ios-simulator-universal/libArchiveRar.a
  [[ ! -e Vendor/ArchiveRar.xcframework ]] || { print -u2 'Move existing ArchiveRar.xcframework aside before rebuilding'; exit 1; }
  xcrun xcodebuild -create-xcframework \
    -library work/rar-codecs/macos-arm64/libArchiveRar.a -headers work/rar-codecs/macos-arm64/Headers \
    -library work/rar-codecs/ios-arm64/libArchiveRar.a -headers work/rar-codecs/ios-arm64/Headers \
    -library work/rar-codecs/ios-simulator-universal/libArchiveRar.a -headers work/rar-codecs/ios-simulator-arm64/Headers \
    -output Vendor/ArchiveRar.xcframework
fi
