# Files access policy

Updated 2026-10-04. ZIP stored/Deflate and integrated native formats share this same output policy. Encryption is not implemented.

## Input

The system Files importer accepts archives from user-granted local folders, external drives, iCloud or third-party providers. Start/stop security-scoped access around the coordinated read. Stream an immutable private snapshot in 256 KiB chunks; do not modify the source or leave a provider document open for preview. Provider-download, permission and I/O errors are surfaced.

## Output

Extract offers app Documents/Extractions or a system folder picker (`.folder`, `asCopy: false`). The picker starts at app Documents but users can browse Files. Present the system controller without a custom header that conflicts with Duo's camera-safe areas. Some compact presentations omit their own close action, so a native Cancel button is supplied in a bottom safe-area inset. System close, outside dismissal where available, and the explicit Cancel action retain preview/navigation and do not extract. The footer consumes safe-area space instead of overlaying the provider's native controls.

Classify before any test write or filesystem mutation:

- Canonical path-component containment within app Documents: writable.
- Foundation `isUbiquitousItem == true`: recognized iCloud destination.
- `volumeIsLocal == true && volumeIsInternal == false`: recognized external local volume.
- Anything else: reject writing. Local-volume metadata alone does not identify local storage; cloud providers cache files locally.

Reject files, symbolic-link roots, known read-only folders and missing/unmounted destinations. Revalidate inside coordination. Metadata permits a write attempt, not a guarantee that I/O will succeed.

Hold the security grant throughout the coordinated directory write, extraction, CRC verification, same-volume rename and rollback. Stream directly into a fresh `.ArchiveDesk-UUID` staging folder on the chosen volume. Publish `Extracted-UUID` only after all selected entries pass. Never merge, replace or delete existing content. Cleanup removes only the owned staging folder. A failed rollback reports its exact unfinished folder; it does not claim cleanup succeeded. No persistent bookmark/standing grant is retained.

Show a location receipt, not a live external document. View the output in Files. Unrestricted ShareLink/fileExporter writes are absent so they cannot bypass the cloud policy. Completed iCloud publication is not confirmed cloud-server upload.

## Limitation

Public iOS APIs do not expose universal provider identity for an arbitrary picker URL. `NSFileProviderManager.getIdentifierForUserVisibleFile` is limited to the caller's own provider/domain. Third-party cached items can have ordinary local-volume properties.

The requested combination of **all Files read/write areas** and **all non-iCloud clouds read-only** is therefore not fully achieved. This build fails closed for unidentified locations, including other apps' local Documents and SMB shares. No guessed provider paths, private identifiers or private APIs are used. Those local areas need a separately verified provenance design; a writable URL alone must not relax the policy.

## Verification

Core tests cover policy, missing/link roots, preserved existing content, CRC and cancellation. Desktop coordinated integration reports skips when the sandbox blocks writes/reads (Cocoa 512/256); skips are not passed tests. Native iOS UI regressions exercise the real folder picker, cancellation and granted app Documents. USB devices, third-party providers, iCloud sync, unplugging during extraction and read-only media require physical-device tests.

## Public sources

- [Directory access](https://developer.apple.com/documentation/uikit/providing-access-to-directories)
- [Document picker](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller)
- [Security-scoped resources](https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource())
- [File coordination](https://developer.apple.com/documentation/foundation/nsfilecoordinator)
- [iCloud metadata](https://developer.apple.com/documentation/foundation/urlresourcevalues/isubiquitousitem)
- [File provider manager](https://developer.apple.com/documentation/fileprovider/nsfileprovidermanager)

SDK public headers were read directly to verify metadata availability and the own-domain restriction.
