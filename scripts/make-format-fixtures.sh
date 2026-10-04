#!/bin/zsh
set -eu
cd "${0:A:h:h}"
task_root="$PWD/work/format-fixtures"
task_reference="$PWD/work/codec-sources/libarchive-3.8.9/libarchive/test"
task_7zip="${SEVENZIP:-$(command -v 7zz || true)}"
[[ -x "$task_7zip" ]] || { print -u2 'Install 7zz or set SEVENZIP to its absolute path'; exit 1; }
mkdir -p "$task_root/input" "$PWD/work/codec-sources"
cp Tests/Fixtures/Input/* "$task_root/input/"
[[ -d "$task_reference" ]] || tar -xJf Vendor/Sources/libarchive-3.8.9.tar.xz -C work/codec-sources
cd "$task_root/input"
"$task_7zip" a -t7z -m0=LZMA2 -ms=on "$task_root/sample.7z" Notes.md Second.md empty.txt 中文.txt 日本語.txt
"$task_7zip" a -t7z -m0=LZMA "$task_root/lzma.7z" Notes.md
"$task_7zip" a -tzip -mm=Deflate "$task_root/deflate.zip" Notes.md empty.txt 中文.txt 日本語.txt
/usr/bin/tar -cf "$task_root/sample.tar" Notes.md empty.txt
/usr/bin/tar -czf "$task_root/sample.tar.gz" Notes.md empty.txt
/usr/bin/tar -cjf "$task_root/sample.tar.bz2" Notes.md empty.txt
"$task_7zip" a -txz "$task_root/sample.tar.xz" "$task_root/sample.tar"
"$task_7zip" a -txz "$task_root/Notes.md.xz" Notes.md
"$task_7zip" a -tgzip "$task_root/Notes.md.gz" Notes.md
"$task_7zip" a -tbzip2 "$task_root/Notes.md.bz2" Notes.md
uudecode -o "$task_root/rar4.rar" "$task_reference/test_read_format_rar_binary_data.rar.uu"
uudecode -o "$task_root/rar5.rar" "$task_reference/test_read_format_rar5_compressed.rar.uu"
uudecode -o "$task_root/rar5-solid.rar" "$task_reference/test_read_format_rar5_multiple_files_solid.rar.uu"
uudecode -o "$task_root/rar-links.rar" "$task_reference/test_read_format_rar.rar.uu"
uudecode -o "$task_root/sample.iso.Z" "$task_reference/test_read_format_iso_2.iso.Z.uu"
uncompress -f "$task_root/sample.iso.Z"
