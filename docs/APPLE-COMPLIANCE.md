# Apple platform and review checklist

Official sources reviewed on 2026-10-03:

- [Get ready for iPhone Duo](https://developer.apple.com/iphone-duo/)
- [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- [Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/)
- [Design for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111466/)
- [Leverage multiple displays and scenes on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111464/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [NSFileCoordinator](https://developer.apple.com/documentation/foundation/nsfilecoordinator)
- [Security-scoped resources](https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource())

## Applied requirements

- Use adaptive system navigation, safe areas, and per-edge layout margins. Avoid fixed screen dimensions and device-model branching.
- Keep interactive content out of reserved regions; let system split views, sheets, menus, and toolbars perform their automatic adaptation.
- Support both iPhone and iPad, flexible window sizes, rotation, keyboard, pointer, Dynamic Type, VoiceOver labels, light/dark appearances, and Reduce Motion.
- Coordinate external document access and balance every successful security-scope start with a stop.
- Open directories with the system document picker, hold scope for the complete coordinated write, and never infer cloud identity from a local cache path. Only verified app Documents/iCloud/external volumes are writable; unknown providers fail closed.
- Publish new UUID extraction folders without overwriting existing files. Report failed rollback after storage disconnection. All output uses the app sandbox or system-picker-granted directories; cloud providers may be writable under the revised 0.3.2 policy.
- Keep all archive processing in process; do not download executable code or rely on spawned command-line tools.
- Protect user data and describe actual capabilities accurately. App Review rules 1.6, 2.1, 2.3, 2.4.1, and 2.4.2 are especially relevant.
- Do not decrypt DRM, execute packages, sideload apps, re-sign packages, or claim malware-scanning behavior.
- Confirm licenses for all archive libraries and every icon/art asset before distribution. Existing character artwork is not assumed commercially licensed.

## 0.3.1 development audit (2026-10-06)

- [Required reason API categories and reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype): the bundled `PrivacyInfo.xcprivacy` declares file metadata in our container (`C617.1`) and explicitly selected documents (`3B52.1`), elapsed task timing (`35F9.1`), observable write-capacity checks (`E174.1`), and displaying available/required bytes on a space error (`85F4.1`). These values are not transmitted off-device. The app has no analytics or tracking SDK; no collected-data or tracking entries are declared. This is not a claim of App Store acceptance.
- [Directory access](https://developer.apple.com/documentation/uikit/providing-access-to-directories): retain the user-selected directory's security scope for the full coordinated read/write; balance successful starts with stops. Missing optional volume metadata is not proof of missing permission.
- [Checking volume capacity](https://developer.apple.com/documentation/foundation/checking-volume-storage-capacity): check the actual destination volume, prefer important-usage capacity for user-requested writes, and treat unavailable values as unknown rather than zero. Only an actual out-of-space error or a reliable insufficient-capacity measurement is reported as a storage-space failure. Decoder allocation and metadata safety limits have separate errors.

## Remaining submission gates

App Store work is not authorized yet. Before any submission: validate on physical iPhone, iPad, and iPhone Duo; run accessibility and localization audits; provide complete metadata and review notes; verify privacy declarations; test file providers and low-space failure; provide codec license notices; and use only rights-cleared artwork.

The 0.3.2 development policy follows system directory authorization and actual writable capability, without attempting universal provider identification. USB and third-party-provider physical-device testing remains a submission gate. See [STORAGE-ACCESS.md](STORAGE-ACCESS.md).
