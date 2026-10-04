#!/bin/zsh
set -eu
cd "${0:A:h:h}"
task_app="${1:?Pass a Release-iphoneos ArchiveDeskIOS.app path}"
task_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$task_app/Info.plist")
task_output="${2:-$PWD/outputs/ArchiveDesk-$task_version-unsigned.ipa}"
[[ "$task_app" = /* && "$task_output" = /* ]] || { print -u2 'Use absolute paths'; exit 1; }
[[ ! -e "$task_output" ]] || { print -u2 'Output exists; refusing to replace it'; exit 1; }
task_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$task_app/Info.plist")
task_platform=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$task_app/Info.plist")
[[ "$task_platform" == iPhoneOS ]] || { print -u2 'Not a device build'; exit 1; }
xcrun vtool -show-build "$task_app/$task_executable" | /usr/bin/grep -q 'platform IOS$'
[[ ! -e "$task_app/_CodeSignature" && ! -e "$task_app/embedded.mobileprovision" ]] || { print -u2 'Expected unsigned app'; exit 1; }
task_stage=$(mktemp -d "$PWD/work/ipa-package.XXXXXX")
mkdir -p "$task_stage/Payload" "${task_output:h}"
ditto --norsrc --noextattr "$task_app" "$task_stage/Payload/ArchiveDeskIOS.app"
(cd "$task_stage"; /usr/bin/zip -q -r "$task_output" Payload)
/usr/bin/unzip -t "$task_output"
shasum -a 256 "$task_output"
print 'Unsigned device IPA: re-sign before installation. Staging retained in work/.'
