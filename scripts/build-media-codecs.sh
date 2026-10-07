#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.1-beta.app/Contents/Developer}"
task_root="$PWD"
task_source="$PWD/work/media-sources"
task_tools="$PWD/work/media-build-tools/bin"
task_rg=$(command -v rg)
export PATH="$task_tools:$PWD/Vendor/MediaSupport:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
[[ ! -d Vendor/ArchiveMedia.xcframework ]] || { print -u2 'Back up the existing media framework first'; exit 1; }
[[ "$(shasum -a 256 Vendor/Sources/ffmpeg-9.0.2.tar.xz | cut -d ' ' -f 1)" == 8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e ]] || exit 1
[[ "$(shasum -a 256 Vendor/Sources/dav1d-1.5.4.tar.xz | cut -d ' ' -f 1)" == 686616b7c69eb88d44459391ab25cac13b6647a3b288835c5784e71c1514a5c5 ]] || exit 1
mkdir -p "$task_source"
[[ -d "$task_source/ffmpeg-9.0.2" ]] || tar -xf Vendor/Sources/ffmpeg-9.0.2.tar.xz -C "$task_source"
[[ -d "$task_source/dav1d-1.5.4" ]] || tar -xf Vendor/Sources/dav1d-1.5.4.tar.xz -C "$task_source"
task_slices=(macos-arm64 ios-arm64 ios-simulator-arm64 ios-simulator-x86_64)
[[ -z "${MEDIA_SLICES:-}" ]] || task_slices=(${=MEDIA_SLICES})
for task_slice in "${task_slices[@]}"; do
  task_arch=aarch64; task_cross=cross-arm64.ini; task_asm=true; task_extra=()
  case "$task_slice" in
    macos-arm64) export MEDIA_SDK=macosx MEDIA_TARGET=arm64-apple-macosx26.0 ;;
    ios-arm64) export MEDIA_SDK=iphoneos MEDIA_TARGET=arm64-apple-ios26.0 ;;
    ios-simulator-arm64) export MEDIA_SDK=iphonesimulator MEDIA_TARGET=arm64-apple-ios26.0-simulator ;;
    ios-simulator-x86_64) export MEDIA_SDK=iphonesimulator MEDIA_TARGET=x86_64-apple-ios26.0-simulator
      task_arch=x86_64; task_cross=cross-x86_64.ini; task_asm=false; task_extra=(--disable-x86asm) ;;
  esac
  task_dir="$PWD/work/media-codecs/$task_slice"
  task_prefix="$task_dir/prefix"
  mkdir -p "$task_dir/ffmpeg" "$task_dir/Headers"
  [[ ! -f "$task_dir/Headers/module.modulemap" ]] || unlink "$task_dir/Headers/module.modulemap"
  export PKG_CONFIG_LIBDIR="$task_prefix/lib/pkgconfig"
  unset PKG_CONFIG_PATH
  if [[ ! -f "$task_prefix/lib/libdav1d.a" ]]; then
    meson setup "$task_dir/dav1d" "$task_source/dav1d-1.5.4" \
      --cross-file "$task_root/Vendor/MediaSupport/$task_cross" \
      --prefix "$task_prefix" --libdir lib --buildtype release --default-library static \
      -Denable_tools=false -Denable_tests=false -Denable_asm="$task_asm"
    ninja -C "$task_dir/dav1d" -j 4
    ninja -C "$task_dir/dav1d" install
  fi
  (
    cd "$task_dir/ffmpeg"
    if [[ ! -f config.h || "${MEDIA_RECONFIGURE:-0}" == 1 ]]; then
      "$task_source/ffmpeg-9.0.2/configure" \
        --prefix="$task_prefix" --cc="$task_root/Vendor/MediaSupport/archivedesk-media-clang" \
        --arch="$task_arch" --target-os=darwin --enable-cross-compile \
        --disable-autodetect --disable-shared --enable-static --enable-pic \
        --disable-everything --disable-programs --disable-doc --disable-debug \
        --disable-avdevice --disable-avfilter --disable-network \
        --disable-audiotoolbox --disable-videotoolbox --disable-securetransport \
        --enable-avcodec --enable-avformat --enable-avutil --enable-swscale --enable-swresample \
        --enable-libdav1d --enable-zlib --pkg-config-flags=--static \
        --extra-cflags="-I$task_prefix/include -O2" --extra-ldflags="-L$task_prefix/lib" \
        --enable-decoder=aac,flac,mjpeg,png,mp3,pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le,h264,hevc,libdav1d,webp,vorbis,opus \
        --enable-parser=aac,flac,mpegaudio,h264,hevc,av1,mjpeg,png,opus,vorbis \
        --enable-demuxer=mov,flac,mp3,aac,wav,matroska,ogg,mjpeg,image_jpeg_pipe,image_png_pipe,image_webp_pipe \
        --enable-protocol=file "${task_extra[@]}"
    fi
    make -j 4
    make install
    ! "$task_rg" -q '^#define CONFIG_(GPL|NONFREE|VERSION3|VIDEOTOOLBOX|AUDIOTOOLBOX) 1' config.h
    ! "$task_rg" -q '^#define CONFIG_.*_(ENCODER|MUXER|HWACCEL) 1' config_components.h
    "$task_rg" -q '^#define CONFIG_PNG_DECODER 1' config_components.h
    "$task_rg" -q '^#define CONFIG_AAC_DEMUXER 1' config_components.h
  )
  archivedesk-media-clang -O2 -fPIC -I "$task_prefix/include" \
    -I "$task_root/Vendor/MediaSupport" -c "$task_root/Vendor/MediaSupport/ArchiveMedia.c" -o "$task_dir/ArchiveMedia.o"
  xcrun libtool -static -o "$task_dir/libArchiveMedia.a" "$task_dir/ArchiveMedia.o" \
    "$task_prefix/lib/libavformat.a" "$task_prefix/lib/libavcodec.a" \
    "$task_prefix/lib/libswscale.a" "$task_prefix/lib/libswresample.a" \
    "$task_prefix/lib/libavutil.a" "$task_prefix/lib/libdav1d.a"
  cp Vendor/MediaSupport/ArchiveMedia.h "$task_dir/Headers/"
done
if [[ "${MEDIA_SLICES:-}" == '' ]]; then
  task_sim="$PWD/work/media-codecs/ios-simulator"
  mkdir -p "$task_sim/Headers"
  [[ ! -f "$task_sim/Headers/module.modulemap" ]] || unlink "$task_sim/Headers/module.modulemap"
  cp Vendor/MediaSupport/ArchiveMedia.h "$task_sim/Headers/"
  xcrun lipo -create work/media-codecs/ios-simulator-arm64/libArchiveMedia.a \
    work/media-codecs/ios-simulator-x86_64/libArchiveMedia.a -output "$task_sim/libArchiveMedia.a"
  xcodebuild -create-xcframework \
    -library work/media-codecs/ios-arm64/libArchiveMedia.a -headers work/media-codecs/ios-arm64/Headers \
    -library "$task_sim/libArchiveMedia.a" -headers "$task_sim/Headers" \
    -library work/media-codecs/macos-arm64/libArchiveMedia.a -headers work/media-codecs/macos-arm64/Headers \
    -output Vendor/ArchiveMedia.xcframework
fi
