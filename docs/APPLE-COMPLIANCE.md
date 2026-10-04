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
- Publish new UUID extraction folders without overwriting existing files. Report failed rollback after storage disconnection. No unrestricted ShareLink write path bypasses the third-party-cloud read-only policy.
- Keep all archive processing in process; do not download executable code or rely on spawned command-line tools.
- Protect user data and describe actual capabilities accurately. App Review rules 1.6, 2.1, 2.3, 2.4.1, and 2.4.2 are especially relevant.
- Do not decrypt DRM, execute packages, sideload apps, re-sign packages, or claim malware-scanning behavior.
- Confirm licenses for all archive libraries and every icon/art asset before distribution. Existing character artwork is not assumed commercially licensed.

## Submission gates

App Store work is not authorized yet. Before any submission: validate on physical iPhone, iPad, and iPhone Duo; run accessibility and localization audits; provide complete metadata and review notes; verify privacy declarations; test file providers and low-space failure; provide codec license notices; and use only rights-cleared artwork.

The requested “all Files read/write regions” coverage is not complete: some legitimate local providers and SMB cannot be distinguished safely from third-party cloud caches with the current public metadata policy. Physical external-storage/iCloud testing remains a submission gate. See [STORAGE-ACCESS.md](STORAGE-ACCESS.md).
