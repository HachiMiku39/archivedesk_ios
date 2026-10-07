#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.1-beta.app/Contents/Developer}"
mkdir -p work/bin
task_sdk=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target arm64-apple-macosx26.0 -isysroot "$task_sdk" -O2 \
  -Dnewlocale=probe_newlocale -Duselocale=probe_uselocale \
  -c Vendor/Support/codec_locale.c -o work/bin/codec-locale-faults.o
xcrun clang -target arm64-apple-macosx26.0 -isysroot "$task_sdk" -O2 \
  Tests/CodecLocaleVerification.c work/bin/codec-locale-faults.o \
  -o work/bin/codec-locale-verification
work/bin/codec-locale-verification
