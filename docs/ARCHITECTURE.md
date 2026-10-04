# Architecture and UI plan

## Product boundary

The mobile app keeps the macOS product's safety goals and pure-data inspection ideas, but not its `posix_spawn`/7zz execution model. Every iOS codec must run in process, have a reviewed license, expose cancellation, and operate with bounded streaming buffers.

The current milestone includes bounded ZIP indexing, stored/Deflate extraction, small-text preview, folder navigation, policy-checked destinations, libarchive/liblzma readers, source-built read-only RAR password decoding, and multi-source ZIP/TAR creation. Encrypted creation, split volumes and dedicated IPA/APK inspection remain separate milestones. ZIP retains strict custom central/local-header validation. RAR handles live only on their synchronous worker thread; models do not retain passwords. See [ARCHIVE-ENGINES.md](ARCHIVE-ENGINES.md).

## File lifecycle

1. The system document importer returns a user-selected URL.
2. The app begins security-scoped access only for the operation lifetime.
3. `NSFileCoordinator` coordinates a read and copies the input into an app-private snapshot.
4. The engine indexes the immutable snapshot and validates paths and declared sizes.
5. Choose app Documents or a system-granted folder. Validate destination policy before writing; hold security scope and coordinate external writes.
6. Stream into a fresh staging directory on that volume, verify CRC/cancellation/capacity, then rename to a new completed directory. Roll back only owned staging content. If a disconnected drive prevents cleanup, report its unfinished folder.

Cloud availability errors are surfaced; the app never assumes a File Provider item is already local.

## Adaptive UI

- Compact width: single-column archive navigation.
- Regular/wide width: folder/file list plus detail using a two-column `NavigationSplitView`. Preview and metadata use `ArrangementView(.split)` on iOS 27.1+; native tabs choose their system-default placement, rather than forcing a sidebar.
- Layout follows available window size and size classes, not a device-name check.
- Scene-owned `WorkspaceModel` retains the archive snapshot, folder path, selection, preview, and task list through rotation, folding, and window resizing.
- Native lists, toolbars, sheets, and safe areas avoid reserved regions automatically. No hinge dimensions or symmetric-inset assumptions exist.
- The file column has an Open action; the detail owns the sole extraction toolbar, avoiding duplicate More menus. Folder selection preserves the native provider controller and supplies an explicit bottom-safe-area Cancel exit where the system presentation lacks one.
- iPad receives keyboard commands, hover-capable native controls, multiple-scene configuration, and resizable layouts.

Verified with public SDK declarations: `ArrangementView`, `reservedRegions(kind:)`, `onHingeChange` and toolbar `axisBehavior` are available from 27.1 and calls are availability-guarded. Toolbars use native primary/secondary placements with a vertical preference on 27.1+. Removing that preference did not fix the fold transition and was reverted. Hinge observations only feed debug diagnostics; content layout follows system regions rather than angles. Native browser navigation is recreated when crossing compact/regular horizontal environments to avoid stale Duo beta navigation chrome. Archive, folder, selected entry, preview and task state remain in the outer model; transient scroll positions are not guaranteed across that boundary.

Current state retention covers the lifetime of one scene during layout/pose changes. Disk-backed process-relaunch restoration is not implemented. Multiple windows have independent workspace models. The foreground-only MVP cancels active work on backgrounding; it does not implement background resumption or a persistent queue.

## Resource policy

The app does not derive a memory ceiling as a percentage of physical RAM. Snapshot and extraction use 256 KiB chunks; text preview is limited to 256 KiB. The index is capped at 100,000 headers/entries and 32 MiB of filename bytes. Vendor allocations have a 128 MiB single-allocation and 256 MiB live-per-thread ceiling; single-threaded XZ and synchronous reader ownership preserve accounting. These are not total RSS limits: Swift buffers and public system zlib/bzip2 allocations are separate. Storage is checked before staging. Native calls can delay cooperative cancellation, especially solid-stream skips; no hard CPU timeout is claimed. Thermal/memory observers, periodic low-space checks and bounded background execution remain later tasks.

The extractor only creates fresh UUID folders and rejects archive links/special-file attributes and file/directory or Unicode/case aliases. Outputs preserve original filename spelling. The finished staging directory is renamed on the same volume after CRC and cancellation checks. Existing content is never merged or replaced. Unknown providers are read-only; see [STORAGE-ACCESS.md](STORAGE-ACCESS.md) for the public-API classification limitation.
