#!/bin/zsh
# Run from an extracted ArchiveDesk device relink kit, not the project root.
set -eu
task_kit="${0:A:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.1-beta.app/Contents/Developer}"
task_rar="${1:-$task_kit/libraries/libArchiveRar.a}"
task_codecs="${2:-$task_kit/libraries/libArchiveCodecs.a}"
task_media="${3:-$task_kit/libraries/libArchiveMedia.a}"
[[ -f "$task_rar" && -f "$task_codecs" && -f "$task_media" ]] || { print -u2 'Pass existing static libraries'; exit 1; }
task_stage=$(mktemp -d "$task_kit/relinked.XXXXXX")
task_sdk=$(xcrun --sdk iphoneos --show-sdk-path)
task_swift="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/iphoneos"
# Honor DEVELOPER_DIR rather than the machine's globally selected Xcode.
task_swift="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/iphoneos"
task_objects=()
while IFS= read -r task_name; do
  [[ "$task_name" != */* && -f "$task_kit/app-objects/$task_name" ]] || exit 1
  task_objects+=("$task_kit/app-objects/$task_name")
done < "$task_kit/object-order.txt"
ditto --norsrc --noextattr "$task_kit/resources/ArchiveDeskIOS.app" "$task_stage/Payload/ArchiveDeskIOS.app"
task_binary="$task_stage/Payload/ArchiveDeskIOS.app/ArchiveDeskIOS"
xcrun --sdk iphoneos clang -Xlinker -reproducible -target arm64-apple-ios26.0 \
  -isysroot "$task_sdk" -Os -Xlinker -no_warn_duplicate_libraries \
  "${task_objects[@]}" -Xlinker -dead_strip -fobjc-link-runtime \
  -L"$task_swift" -L/usr/lib/swift -lz -lbz2 -liconv \
  "$task_codecs" "$task_rar" "$task_media" -o "$task_binary"
# Xcode's original strip step removes global symbols; stripping here is optional
# for operation but matches the published application's release layout.
xcrun strip -x "$task_binary"
xcrun vtool -show-build "$task_binary"
(cd "$task_stage"; /usr/bin/zip -q -r "$task_stage/ArchiveDesk-relinked-unsigned.ipa" Payload)
/usr/bin/unzip -t "$task_stage/ArchiveDesk-relinked-unsigned.ipa"
shasum -a 256 "$task_binary" "$task_stage/ArchiveDesk-relinked-unsigned.ipa"
print "Unsigned relinked IPA: $task_stage/ArchiveDesk-relinked-unsigned.ipa"
print 'Re-sign with your own Apple certificate/profile before installation.'
