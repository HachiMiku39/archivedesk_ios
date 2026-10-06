#!/bin/zsh
# Package only an already-verified native Release device build and committed source.
set -eu
cd "${0:A:h:h}"
task_dd="${1:?Pass the absolute ArchiveDesk DerivedData path}"
task_app="$task_dd/Build/Products/Release-iphoneos/ArchiveDeskIOS.app"
task_objects="$task_dd/Build/Intermediates.noindex/ArchiveDeskIOS.build/Release-iphoneos/ArchiveDeskIOS.build/Objects-normal/arm64"
task_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$task_app/Info.plist")
task_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$task_app/Info.plist")
[[ "$task_dd" = /* && -f "$task_objects/ArchiveDeskIOS.LinkFileList" ]] || exit 1
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { print -u2 'Commit the corresponding tracked source first'; exit 1; }
task_ipa="$PWD/outputs/ArchiveDesk-$task_version-unsigned.ipa"
task_source="$PWD/outputs/ArchiveDesk-$task_version-source.tar.gz"
task_relink="$PWD/outputs/ArchiveDesk-$task_version-relink-kit.tar.gz"
task_sums="$PWD/outputs/ArchiveDesk-$task_version-SHA256SUMS.txt"
for task_output in "$task_ipa" "$task_source" "$task_relink" "$task_sums"; do
  [[ ! -e "$task_output" ]] || { print -u2 "Refusing to overwrite $task_output"; exit 1; }
done
zsh scripts/package-unsigned-ipa.sh "$task_app" "$task_ipa"
git archive --format=tar.gz --prefix="ArchiveDesk-$task_version-source/" --output="$task_source" HEAD
task_kit=$(mktemp -d "$PWD/work/relink-$task_version.XXXXXX")
mkdir -p "$task_kit/app-objects" "$task_kit/libraries" "$task_kit/resources"
while IFS= read -r task_object; do
  [[ "$task_object" = "$task_objects/"*.o && -f "$task_object" ]] || exit 1
  cp "$task_object" "$task_kit/app-objects/"
  print -r -- "${task_object:t}" >> "$task_kit/object-order.txt"
done < "$task_objects/ArchiveDeskIOS.LinkFileList"
cp Vendor/ArchiveRar.xcframework/ios-arm64/libArchiveRar.a "$task_kit/libraries/"
cp Vendor/ArchiveCodecs.xcframework/ios-arm64/libArchiveCodecs.a "$task_kit/libraries/"
ditto --norsrc --noextattr "$task_app" "$task_kit/resources/ArchiveDeskIOS.app"
# Delete only the copied executable: original build remains intact.
[[ -f "$task_kit/resources/ArchiveDeskIOS.app/ArchiveDeskIOS" ]] || exit 1
unlink "$task_kit/resources/ArchiveDeskIOS.app/ArchiveDeskIOS"
cp ArchiveDeskIOS/ThirdParty/CodecNotices.txt "$task_kit/"
cp scripts/relink-ios.sh "$task_kit/relink.sh"
tar -czf "$task_kit/modified-rar-sources.tar.gz" -C work/rar-sources \
  C/Alloc.c CPP/Common/MyWindows.cpp CPP/7zip/Crypto/Rar5Aes.cpp \
  CPP/7zip/Archive/Rar/RarHandler.cpp CPP/7zip/Archive/Rar/Rar5Handler.cpp
cp docs/RELINK-KIT-README.md "$task_kit/README.md"
task_hash=$(shasum -a 256 "$task_ipa" | awk '{print $1}')
TASK_RELEASE_VERSION="$task_version" TASK_RELEASE_BUILD="$task_build" TASK_RELEASE_SHA="$task_hash" \
  perl -pi -e 's/\@VERSION\@/$ENV{TASK_RELEASE_VERSION}/g; s/\@BUILD\@/$ENV{TASK_RELEASE_BUILD}/g; s/\@IPA_SHA\@/$ENV{TASK_RELEASE_SHA}/g' "$task_kit/README.md"
(cd "$task_kit"; find . -type f ! -name SHA256SUMS -print | LC_ALL=C sort | while IFS= read -r task_file; do shasum -a 256 "$task_file"; done > SHA256SUMS)
tar -czf "$task_relink" -C "${task_kit:h}" "${task_kit:t}"
(cd outputs; shasum -a 256 "${task_ipa:t}" "${task_source:t}" "${task_relink:t}" > "${task_sums:t}")
print "Relink kit retained for verification: $task_kit"
print 'Verify relink.sh before uploading all four release assets.'
