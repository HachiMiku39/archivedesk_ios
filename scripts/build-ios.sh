#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
task_sdk="${1:-iphoneos}"
task_configuration="${2:-Debug}"
case "$task_sdk" in
  iphoneos) task_destination='generic/platform=iOS' ;;
  iphonesimulator) task_destination='generic/platform=iOS Simulator' ;;
  *) print -u2 'Use iphoneos or iphonesimulator'; exit 2 ;;
esac
xcodebuild -project ArchiveDeskIOS.xcodeproj -scheme ArchiveDeskIOS \
  -configuration "$task_configuration" -sdk "$task_sdk" \
  -destination "$task_destination" CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath "work/Build-$task_sdk-$task_configuration" build
