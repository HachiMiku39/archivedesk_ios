# iOS encoding fixes — 0.3.3 build 10

Development verification, 2026-10-23. Corresponds to 0.3.3 Beta 2 (build 10); publication packaging is separate from this simulator test run.

## Changes

- Independent ZIP filename and text-body encoding menus, localized in English, Simplified Chinese and Japanese.
- ZIP UTF-8 flags and CRC-valid Unicode path extras retain precedence. Unflagged names try strict UTF-8 and conservative regional-codepage detection, then CP437. Manual filename selection rebuilds the current index without copying the archive again; an unsuccessful reindex preserves the previous snapshot/index.
- Text Auto accepts strict UTF-8/BOM UTF-16 before conservative legacy detection. Manual options include GBK, GB18030, CP932, Big5, CP949, CP437, CP850, Windows-1252, Windows-1251, CP866 and UTF-8/UTF-16LE/BE. Ambiguous text may require an explicit choice; this is not universal encoding detection.
- Conversion uses the already-linked open-source system iconv dependency, without a downloaded detector or new bundled binary. Unicode Auto decoding remains in Swift. Binary controls, malformed BOMs and lossy conversion are rejected.
- ZIP Stored/Deflate preview and extraction use the strict parser's validated local-header/payload offsets. Raw zlib Deflate avoids mismatched filename interpretations in a second archive reader. Length, end-of-stream, compressed-byte consumption, CRC, path safety, rollback and cancellation checks remain enforced.
- Encoding work runs off the main actor. Verified retry bytes are bounded to 256 KiB and cleared on selection/folder changes, successful import, cancellation, backgrounding and memory warnings. No password or plaintext preview history is persisted. Unsupported encrypted ZIP stays blocked; password RAR retains its existing decryption/integrity gates.
- Public CArchive headers and their rebuild source now expose existing public iconv/zlib APIs; vendored static libraries were not replaced.

## Reproduction and regression

The user-supplied unencrypted ZIP has nine entries. Its three Chinese names are unmarked GBK, and its 3,985-byte TXT body is also GBK. Checks cover correct names, readable text, intentionally wrong UTF-8 followed by manual GBK recovery, and exact output lengths/CRCs for all nine files. The source archive remains unchanged; private payloads are not tracked or bundled.

Host commands, from the repository root:

```sh
zsh scripts/verify-encoding.sh /path/to/legacy.zip
zsh scripts/verify-core.sh
zsh scripts/verify-formats.sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer zsh scripts/verify-packing-rar.sh
```

Additional synthetic checks cover Unicode-extra precedence/CRC/traversal, CP437, every manual codepage, malformed Unicode, binary rejection, full-cap UTF-8 expansion, Deflate chunk boundaries (including empty and 2 MiB payloads), cache lifecycle, failed reindex preservation and encrypted-ZIP gating. Existing packing/RAR regression includes eight encrypted RAR variants and wrong-password rollback.

Simulator target: **ArchiveDesk iPhone 18 Pro, iOS 27.2**, one device only. Focused native tests: `testLegacyEncodingPreviewAndRecovery`, `testOriginalLegacyZIPPreviewAndExtraction`, `testDeflatePreviewAndExtraction` in the `ArchiveDeskIOS-DuoDebug` scheme. The optional original ZIP is supplied locally as ignored `work/encoding-fixtures/UserLegacy.zip` and is skipped when absent.

## Verified results

- Encoding verification: **67 checks passed**, including all nine original ZIP outputs and their CRCs.
- Core verification: **115 checks passed**, with two explicit host-only coordinated-read/write integration skips; these are not claimed as host passes.
- Format regression: **36 result groups passed** (readers, CP437 Deflate, corruption, unsafe paths/links and cancellation).
- Packing/RAR regression: **20 result groups passed**, including ZIP/TAR round trips, the 20 MiB local-folder case, a 1,500-file ZIP and eight password RAR variants.
- Final simulator run: **3 native UI tests passed, 0 failures, 0 skips**. This includes original Chinese directory names, GBK text preview, selected TXT extraction, deliberately wrong text/file-name encodings followed by manual recovery, and CP437/Deflate preview/extraction.
- Final installed simulator App reports `CFBundleVersion = 10`; original user ZIP SHA-256 remains `fed6a7189e4af2818464137393aa01b326dd6ad429f2cba4ded03967b46de59b`.
- Native screenshots were visually inspected: Chinese body text is readable and the selected TXT extraction receipt shows success. The final result bundle is `work/Build-iphonesimulator-Debug/Logs/Test/Test-ArchiveDeskIOS-DuoDebug-2026.10.23_09-34-24-+0800.xcresult`; exported private screenshots remain ignored under `work/encoding-screenshots/`.

The temporary project copy of the private ZIP was removed after verification. To rerun the optional native reproduction, supply that ignored fixture again. The original Downloads ZIP was neither modified nor removed.

No physical iPhone/iPad, Duo folding, USB provider, or AV1 playback performance claim is made for this encoding-only change. The subsequent publication includes a separately built unsigned device IPA and corresponding source/relink materials; simulator verification is not physical-device performance evidence.
