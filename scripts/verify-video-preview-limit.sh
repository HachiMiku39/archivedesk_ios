#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
mkdir -p work/bin
xcrun clang -Wall -Wextra -Werror Tests/VideoPreviewLimitVerification.c -I Vendor/MediaSupport \
  -L Vendor/ArchiveMedia.xcframework/macos-arm64 -lArchiveMedia -lz -liconv \
  -o work/bin/video-preview-limit-verification
work/bin/video-preview-limit-verification "$@"
