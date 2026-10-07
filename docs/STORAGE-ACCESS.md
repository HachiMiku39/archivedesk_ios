# Files access policy

Updated 2026-10-06 for 0.3.2 development. Extraction and ZIP/TAR packing share this output policy. Password-protected RAR is supported; encrypted ZIP/7z is not.

## Input

The system Files importer accepts archives from user-granted local folders, external drives, iCloud or third-party providers. Start/stop security-scoped access around the coordinated read. Stream an immutable private snapshot in 256 KiB chunks; do not modify the source or leave a provider document open for preview. Provider-download, permission and I/O errors are surfaced.

## Output

Extract offers app Documents/Extractions or a system folder picker (`.folder`, `asCopy: false`). The picker starts at app Documents but users can browse Files. Present the system controller without a custom header that conflicts with Duo's camera-safe areas. Some compact presentations omit their own close action, so a native Cancel button is supplied in a bottom safe-area inset. System close, outside dismissal where available, and the explicit Cancel action retain preview/navigation and do not extract. The footer consumes safe-area space instead of overlaying the provider's native controls.

Use iOS authorization and provider write capability, not storage provenance:

- App Documents may be used directly within the app sandbox.
- Other destinations must come from the system directory picker. This includes local Downloads, USB storage, iCloud, third-party providers and SMB when the provider supports directory access and writing.
- Unknown volume/provider metadata does not reject a selected directory. Descriptive labels such as iCloud or external volume do not confer access or bypass the sandbox.
- The user explicitly removed the previous third-party-cloud read-only product restriction on 2026-10-06.

Reject files, symbolic-link roots, known read-only folders and missing/unmounted destinations. Revalidate inside coordination. Metadata permits a write attempt, not a guarantee that I/O will succeed.

Hold the security grant throughout the coordinated directory write, extraction, CRC verification, same-volume rename and rollback. Stream directly into a fresh `.ArchiveDesk-UUID` staging folder on the chosen volume. Publish `Extracted-UUID` only after all selected entries pass. Never merge, replace or delete existing content. Cleanup removes only the owned staging folder. A failed rollback reports its exact unfinished folder; it does not claim cleanup succeeded. No persistent bookmark/standing grant is retained.

Show a location receipt, not a live external document. View the output in Files. Completed publication into a provider directory is not confirmation of cloud-server upload. No additional unrestricted export path is introduced by this change.

## Limitation

Public iOS APIs do not expose universal provider identity for an arbitrary picker URL. `NSFileProviderManager.getIdentifierForUserVisibleFile` is limited to the caller's own provider/domain. Third-party cached items can have ordinary local-volume properties.

Universal provider identification is not required by the revised policy. No guessed provider paths, private identifiers, manual claims of being local, or private APIs are used. A picked URL is not a promise of successful I/O: access can be revoked, a device can disconnect, or a provider can reject writes. Actual coordination/write errors are surfaced and owned staging cleanup is attempted without modifying pre-existing content.

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
