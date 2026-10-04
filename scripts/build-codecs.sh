#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.1-beta.app/Contents/Developer}"
task_root="$PWD"
task_source="$task_root/work/codec-sources"
mkdir -p "$task_source" "$task_root/work/codecs" "$task_root/Vendor/Sources"
function obtain() {
  local name="$1" digest="$2" url="$3"
  if [[ ! -f "$task_source/$name" && -f "$task_root/Vendor/Sources/$name" ]]; then
    cp "$task_root/Vendor/Sources/$name" "$task_source/$name"
  fi
  if [[ ! -f "$task_source/$name" ]]; then curl -fL "$url" -o "$task_source/$name"; fi
  [[ "$(shasum -a 256 "$task_source/$name" | cut -d ' ' -f 1)" == "$digest" ]] || { print -u2 'Source checksum mismatch'; exit 1; }
}
obtain libarchive-3.8.9.tar.xz 888c934f9d95648ecb9163dc8e23ab80a476ecb81a8f1154704a227b5b676dde https://github.com/libarchive/libarchive/releases/download/v3.8.9/libarchive-3.8.9.tar.xz
obtain xz-5.8.4.tar.gz 0014c7886930454fe8bd4228665b51af55eeae560ea135c9c4cd33f55b2591d9 https://github.com/tukaani-project/xz/releases/download/v5.8.4/xz-5.8.4.tar.gz
[[ -d "$task_source/libarchive-3.8.9" ]] || tar -xJf "$task_source/libarchive-3.8.9.tar.xz" -C "$task_source"
[[ -d "$task_source/xz-5.8.4" ]] || tar -xzf "$task_source/xz-5.8.4.tar.gz" -C "$task_source"
cp "$task_source/libarchive-3.8.9.tar.xz" "$task_source/xz-5.8.4.tar.gz" Vendor/Sources/
for task_slice in macos-arm64 ios-arm64 ios-simulator-arm64 ios-simulator-x86_64; do
  case "$task_slice" in
    macos-arm64) task_sdk=macosx; task_target=arm64-apple-macosx26.0; task_host=aarch64-apple-darwin; ;;
    ios-arm64) task_sdk=iphoneos; task_target=arm64-apple-ios26.0; task_host=aarch64-apple-ios; ;;
    ios-simulator-arm64) task_sdk=iphonesimulator; task_target=arm64-apple-ios26.0-simulator; task_host=aarch64-apple-ios; ;;
    ios-simulator-x86_64) task_sdk=iphonesimulator; task_target=x86_64-apple-ios26.0-simulator; task_host=x86_64-apple-ios; ;;
  esac
  task_dir="$task_root/work/codecs/$task_slice"
  task_sysroot="$(xcrun --sdk "$task_sdk" --show-sdk-path)"
  task_cc="$(xcrun --sdk "$task_sdk" --find clang)"
  task_flags="-target $task_target -isysroot $task_sysroot -O2 -fPIC"
  task_bounded_flags="$task_flags -include $task_root/Vendor/Support/codec_allocator.h"
  mkdir -p "$task_dir/xz" "$task_dir/archive" "$task_dir/Headers"
  "$task_cc" -target "$task_target" -isysroot "$task_sysroot" -O2 -c Vendor/Support/codec_allocator.c -o "$task_dir/codec_allocator.o"
  "$task_cc" -target "$task_target" -isysroot "$task_sysroot" -O2 -c Vendor/Support/codec_locale.c -o "$task_dir/codec_locale.o"
  if [[ ! -f "$task_dir/xz/src/liblzma/.libs/liblzma.a" ]]; then
    (cd "$task_dir/xz"
      "$task_source/xz-5.8.4/configure" --host="$task_host" --disable-shared --enable-static --disable-nls --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-scripts --disable-doc --enable-threads=no --disable-dependency-tracking CC="$task_cc" CFLAGS="$task_flags" CPP="$task_cc $task_flags -E" > configure.log 2>&1
      make -j8 -C src/liblzma CFLAGS="$task_bounded_flags" > build.log 2>&1)
  fi
  if [[ ! -f "$task_dir/archive/.libs/libarchive.a" ]]; then
    (cd "$task_dir/archive"
      "$task_source/libarchive-3.8.9/configure" --host="$task_host" --disable-shared --enable-static --disable-bsdtar --disable-bsdcat --disable-bsdcpio --disable-bsdunzip --disable-xattr --disable-acl --disable-dependency-tracking --without-openssl --without-xml2 --without-expat --without-libb2 --without-lz4 --without-zstd --without-cng --without-libiconv-prefix CC="$task_cc" CFLAGS="$task_flags" CPP="$task_cc $task_flags -E" CPPFLAGS="-I$task_source/xz-5.8.4/src/liblzma/api" LDFLAGS="-L$task_dir/xz/src/liblzma/.libs" LIBS="$task_dir/codec_allocator.o" PKG_CONFIG=/usr/bin/false LZMA_PC_CFLAGS="-I$task_source/xz-5.8.4/src/liblzma/api" LZMA_PC_LIBS="$task_dir/xz/src/liblzma/.libs/liblzma.a" > configure.log 2>&1
      make -j8 libarchive.la CFLAGS="$task_bounded_flags" LIBS="" > build.log 2>&1)
  fi
  xcrun libtool -static -o "$task_dir/libArchiveCodecs.a" "$task_dir/archive/.libs/libarchive.a" "$task_dir/xz/src/liblzma/.libs/liblzma.a" "$task_dir/codec_allocator.o" "$task_dir/codec_locale.o"
  cp "$task_source/libarchive-3.8.9/libarchive/archive.h" "$task_source/libarchive-3.8.9/libarchive/archive_entry.h" "$task_root/Vendor/Support/module.modulemap" "$task_root/Vendor/Support/ArchiveCodecs.h" "$task_dir/Headers/"
  print "Built $task_slice"
done
mkdir -p "$task_root/work/codecs/ios-simulator-universal"
xcrun lipo -create "$task_root/work/codecs/ios-simulator-arm64/libArchiveCodecs.a" "$task_root/work/codecs/ios-simulator-x86_64/libArchiveCodecs.a" -output "$task_root/work/codecs/ios-simulator-universal/libArchiveCodecs.a"
task_output="$task_root/Vendor/ArchiveCodecs.xcframework"
[[ ! -e "$task_output" ]] || { print -u2 'ArchiveCodecs.xcframework already exists; move it aside before rebuilding.'; exit 1; }
xcrun xcodebuild -create-xcframework \
  -library "$task_root/work/codecs/macos-arm64/libArchiveCodecs.a" -headers "$task_root/work/codecs/macos-arm64/Headers" \
  -library "$task_root/work/codecs/ios-arm64/libArchiveCodecs.a" -headers "$task_root/work/codecs/ios-arm64/Headers" \
  -library "$task_root/work/codecs/ios-simulator-universal/libArchiveCodecs.a" -headers "$task_root/work/codecs/ios-simulator-arm64/Headers" \
  -output "$task_output"
