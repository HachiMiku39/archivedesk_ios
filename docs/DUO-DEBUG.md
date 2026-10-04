# iPhone Duo debug guide

Updated 2026-10-04 (Asia/Shanghai). Xcode 27.2 beta 2, build 27B5028f. Deployment target remains 26.0, device family 1 and 2.

User verification on 2026-10-04 confirms the Duo outer display rotates correctly at 0°, 90° and 270°. This supersedes the current product-level rotation concern; the historical XCTest window-axis assertion failure remains recorded below as a test-driver discrepancy, not an unresolved user-observed rendering failure. No new automated pass is inferred from this report.

## Implemented

Format/icon follow-up on 2026-10-04: the final 11:50:43 Duo native suite passed 7/7 with no failures/skips. It includes ordinary/CP437 Deflate and solid 7z preview/extraction, Chinese/Japanese 7z filenames, readable notices, coordinated Files access, picker cancellation and rotation state retention. Native Release Simulator arm64+x86_64 build also passed. The later public-release preparation replaces the previously tested Mac artwork with a neutral archive-box icon and passes an unsigned arm64 device Release build. See ARCHIVE-ENGINES.md for codec/resource limits; this is not physical USB/iCloud or signed-device evidence.

- Adaptive native tabs using the system-default placement. Forcing sidebar placement hid the section entries beside the split browser on the current Duo beta; removing that override restored the three native tabs.
- Two-column list/detail navigation; compact collapse is handled by SwiftUI.
- In a regular environment, iOS 27.1+ ArrangementView arranges the preview and metadata using active division regions and available space. iOS 26 and compact windows show an inline preview and metadata.
- Toolbar items use Apple-defined primary/secondary placements with a vertical preference on 27.1+. Removing the preference did not fix folding and was reverted. Navigation chrome is rebuilt when crossing compact/regular horizontal environments, while workspace data remains in the outer model.
- Scene-owned navigation, archive snapshot, preview, and task state; geometry/hinge observation never resets these values.
- Debug-only information rows show window dimensions, asymmetric insets, active divisions, hinge status, folder, and selection.
- `--demo-archive` provides a deterministic local fixture containing English, Chinese, and Japanese stored text files.

## Toolchain status

Xcode's first-launch system components and **iOS 27.2 beta 2 runtime (24B5089g)** have been installed through Xcode. Device Hub can create and boot an iPhone 18 Pro running 27.2. Its model list does not offer iPhone Duo for this runtime.

Apple's Xcode 27.2 release notes explicitly direct developers to **Xcode 27.1 beta** for iPhone Duo SDK and simulator support. These are parallel beta branches; a newer version number does not imply Duo support. The user authorized parallel installation on 2026-10-04. Apple's signed XIP has been verified, expanded with macOS Archive Utility and installed at `/Applications/Xcode-27.1-beta.app` (xcodebuild version 27A9269). The existing `/Applications/Xcode-beta.app` 27.2 is preserved; global xcode-select is unchanged. iOS 27.1 Components/runtime installation is complete.

The updated UI suite covers coordinated-read snapshot preview, preview/rotation retention, local extraction receipt, and actual system-folder selection/cancellation/coordinated extraction. All four passed using Xcode 27.1 on iPhone 18 Pro / iOS 27.2. ShareLink is now removed to enforce the third-party-cloud read-only policy. The initially hidden iPad archive column remains fixed (`columnVisibility = .all`). Compact toolbar overflow is opened by the test before selecting Extract; its generated menu uses the label rather than the original identifier.

Native 27.1 Debug and Release simulator builds succeeded. Command-line builds using the new SwiftUI State macro cannot launch its nested sandbox here (`sandbox_apply: Operation not permitted`); this is a host sandbox limitation, not an SDK-symbol error. Native Xcode builds are the verification path. Desktop NSFileCoordinator integration also reports explicit skipped checks; native iOS tests exercise its real read/write paths.

After unlocking, iOS 27.1 platform/runtime installation was confirmed complete. ArchiveDesk iPhone Duo / 27.1 was created and booted; Device Hub exposes Closed, Book and Open controls. iPad's four-test suite passed after waiting for the system folder button to become hittable with a stable frame. Results are retained in `work/storage-271-ipad-272-stable.xcresult`.

The overnight inner-display run, `work/storage-duo-271-open-third.xcresult` (02:12 on 2026-10-04), had two successes and two failures, with no skips. Tasks/Information navigation queries failed while section entries were absent. This historical result is retained; subsequent tab-placement fixes restored the entries.

Duo testing identified additional assumptions in the old suite: off-screen compact Form receipts are virtualized, popup buttons appear before their expansion animation ends, and some wide system folder sheets use an outside-dismiss region. Tests now account for these actual UI behaviors. A custom folder-picker header overlapped the outer-display camera area and has been removed. The 10:15 ordinary-iPhone run then exposed a genuine missing-exit issue: neither native Cancel nor outside dismissal existed. A native Cancel button now consumes a bottom safe-area inset instead of overlaying provider controls. The 10:19 ordinary-iPhone run passed 4/4 with zero skips (`work/storage-phone-272-footer-final.xcresult`), including cancellation, retained preview, reopening and coordinated write.

Apple's [Duo preparation talk](https://developer.apple.com/videos/play/tech-talks/111461/) explains that the inner display does not honor supported interface orientations and has regular horizontal/vertical size classes. Fully open Duo was observed reporting zero reserved divisions, so division count cannot classify its display. The updated test reads the actual phone regular/regular environment: ordinary/outer displays require swapped window dimensions; the regular/regular phone environment requires stable geometry and retained preview after physical orientation requests. This does not prove a visible inner-display rotation. Actual Device Hub pose checks are recorded separately.

On 2026-10-04 at 09:44, `work/storage-duo-271-open-final.xcresult` recorded 4/4 passing cases and zero skips after default tab placement and the environment diagnostic change. Subsequent toolbar/chrome changes require new runs; this result is retained as an intermediate pass, not the final build's verification.

The 10:08 final expanded-portrait run, `work/storage-duo-271-open-portrait-final.xcresult`, recorded 4/4 passing cases and zero skips. The sidebar now has Open only; the detail column owns the sole extraction toolbar. In narrow regular windows, a first tap on the obscured detail toolbar can dismiss the file-column overlay; the test re-queries the exposed More control before opening Extract. Stable hit-target waits alone did not fix this presentation behavior; those failed runs are retained.

The iPad Pro 11-inch (M5) / 27.2 regression at 10:11, `work/storage-ipad-272-final-native-tabs.xcresult`, passed all four cases with zero skips before the bottom Cancel footer. The latest 10:30 run, `work/storage-ipad-272-footer-final.xcresult`, also passed 4/4 with zero skips, including the final footer, toolbar, browser identity, actual window-axis rotation and system-granted coordinated write.

The expanded-portrait Duo run at 10:23, `work/storage-duo-271-footer-final.xcresult`, passed 4/4 with zero skips after the bottom Cancel fix. Native Device Hub also showed the footer below Files controls, with its Open action unobstructed. This is the latest inner-display UI verification; it does not resolve the separate outer orientation failure or validate physical external media.

At 10:29, the final picker was manually kept open through Closed → Book → Open. App Documents remained selected, native Open and the bottom Cancel remained visible in each settled pose, and Cancel returned to the same Notes.md preview without an extraction receipt. The narrow regular file-column overlay was dismissed normally to inspect the retained text. These are actual native observations, not the black XCTest image attachments.

The 09:54 closed-display run, `work/storage-duo-271-closed-first-new.xcresult`, recorded 3/4 successes. Coordinated read, folder-picker cancellation/coordinated write, and local extraction passed. The rotation assertion failed: XCUIDevice's portrait/landscape requests did not exchange the accessible window axes (it remained in a landscape frame), and the before/after screenshot payloads were identical. Native Device Hub rotation visibly worked, but the automation's active-display/orientation association remains unconfirmed. Do not count that automated case as passed.

Manual checks of the chrome-rebuild version restored visible Back/Open controls and a working More → Extract menu after Open → Closed, with Notes.md still selected. This was repeated at 10:28 on the final toolbar version, with the vertical axis preference restored and no intervening tab switch. Earlier system-picker checks retained app Documents through Closed → Book → Open; outside dismissal retained preview. Its adaptive buttons move during presentation, so stale-coordinate manual confirmation is not evidence of successful extraction. A test-only empty Untitled folder was created by a moving New Folder button; no user document was overwritten. Outer display rotation was visually observed with retained Notes content.

Earlier manual checks showed a blank/unresponsive toolbar after Open → Closed, recovering after tab switching. Rebuilding navigation chrome at compact/regular transitions restored Back/Open and working extraction without that tab-switch workaround in the later manual check. Repeated fold cycles, long-running extraction/cancellation during folds, full accessibility audits and physical-device grants remain pending; a single successful transition does not establish exhaustive coverage.

Exported `XCUIScreen.main` attachments from the open-display runs are entirely black. The added `app.screenshot()` attachments also render black on the inner display, despite native Device Hub showing the app. Neither is valid visual pass evidence. Use native Device Hub observations for inner-display visual checks, and separately inspect ordinary/outer screenshot attachments. The earlier overnight work stopped when the Mac locked; it was resumed during the morning.

Debug builds now explicitly generate DWARF symbols. The empty-dSYM warning is gone. Test runs contain a “Debug session ended with code 9: killed” warning at teardown, including otherwise passing ordinary-device runs. This warning has not been classified as an application crash; Duo test failures are reported separately above.

An SDK build does not require an installed runtime. Generic builds and ordinary iPhone/iPad rotations alone do not prove Duo rendering or hinge events. The initial Duo failures and subsequent runs are retained rather than reclassified as passes.

## Reproduce after installing an appropriate runtime in Xcode

1. Open `ArchiveDeskIOS.xcodeproj` in Xcode 27.1 beta after installing its iOS 27.1 runtime. Select the shared ArchiveDeskIOS-DuoDebug scheme and an iPhone Duo device in Device Hub.
2. This scheme supplies `--demo-archive` automatically. The argument is honored only by Debug builds. Cmd-U runs the four read/write/layout UI regressions; it does not automate hinge movement.
3. Run. Enter Documents, select Notes.md, and confirm its preview.
4. Open/close the device using Device Hub's supported controls. Check that folder, selection, preview, and archive remain unchanged. The fold must not cause duplicate imports/extractions.
5. Test fully open, partially folded, outer display, portrait, landscape, both sides of Split View, and small resizable windows. Verify system controls avoid cameras and fold, and metadata stays reachable.
6. Run extraction; fold/rotate without changing its task status. Try cancellation and verify no incomplete directory is published. Choose a granted folder in Files; non-iCloud cloud providers are read-only. Backgrounding intentionally cancels active work in this foreground-only milestone.
7. Repeat with larger Dynamic Type, VoiceOver, light/dark appearance, English/简体中文/日本語, iPad keyboard and pointer. Cmd-O opens; Cmd-E extracts the selected supported file.

Avoid prescribing `simctl` hinge commands: none have been verified here. Use the controls exposed by Device Hub.

## Regression scope

`zsh scripts/verify-core.sh` builds a Mac-host executable from the shared Swift sources. It exercises real archive bytes, CRC corruption and cleanup, streaming extraction, cancellation, Unicode/case aliases, CP437, links, encrypted/deflated rejection, ZIP64 EOCD and entry fields, folder routing, and workspace retention when diagnostics change. It does not exercise SwiftUI layout or simulate hardware.

## Official sources

- [Xcode 27.2 release notes: Duo requires the 27.1 branch](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes)
- [Xcode 27.1 beta release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes)
- [Preparing for Duo](https://developer.apple.com/iphone-duo/)
- [Adaptive layouts and arrangements](https://developer.apple.com/videos/play/tech-talks/111463/)
- [Multiple displays and scenes](https://developer.apple.com/videos/play/tech-talks/111464/)
- [Duo design guidelines](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)

The SDK's public Swift interfaces were read directly to verify symbol names and availability; no private API is used.
