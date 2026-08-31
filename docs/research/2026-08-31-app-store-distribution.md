# SnapAssist: Mac App Store and direct-download distribution audit

**Research date:** 2026-08-31
**Scope:** A native macOS menu-bar utility that discovers, observes, moves, and resizes windows belonging to other apps through `AXUIElement`, with optional per-window thumbnails from ScreenCaptureKit.
**Source policy:** Only current first-party Apple documentation, Apple policy, and an Apple DTS response are used for platform and distribution claims. Repository observations are identified separately.

## Executive verdict

The full SnapAssist product should ship as a **Developer ID-signed, Hardened Runtime-enabled, notarized direct download**. A new, full-featured Mac App Store build is not a supported technical target because its core cross-app Accessibility behavior conflicts with mandatory App Sandbox.

| Channel | Full AX window control | ScreenCaptureKit thumbnails | Supported conclusion |
|---|---:|---:|---|
| Mac App Store | No supported path | Technically available subject to consent and privacy handling | Do not make this the primary release target |
| Direct download, notarized | Yes, after the user grants Accessibility | Yes, after separate Screen Recording consent | Recommended release channel |

This is not merely a speculative App Review risk:

1. Mac App Store apps must be appropriately sandboxed under [App Review Guideline 2.4.5(i)](https://developer.apple.com/app-store/review/guidelines/), and Apple separately states that App Sandbox is required for Mac App Store distribution in [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox) and [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution).
2. Apple's current sandbox documentation lists **use of Accessibility APIs in assistive apps** among the functionality that is incompatible with App Sandbox: [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox).
3. Apple's AX documentation describes `AXUIElement` as the interface assistive applications use to communicate with and control other macOS applications: [AXUIElement.h](https://developer.apple.com/documentation/applicationservices/axuielement_h).
4. In July 2026, Apple DTS answered the exact case of an `AXUIElement` window manager: “the Accessibility APIs are not supported in sandboxed apps.” DTS explicitly declined to make a policy determination about exceptions or existing Store apps: [Apple Developer Forums thread 836644](https://developer.apple.com/forums/thread/836644).

**Inference:** A currently listed third-party window manager is not evidence that Apple offers a public exemption to a new app. It may reflect older policy, a grandfathered binary, a private arrangement, or facts that are not visible externally. There is no general-purpose Accessibility sandbox exception in Apple's public entitlement catalog: [Entitlements](https://developer.apple.com/documentation/bundleresources/entitlements).

## Mac App Store feasibility

### Why the full app is blocked

SnapAssist does not merely read its own UI. It creates Accessibility objects for unrelated processes, observes their windows, reads geometry, and writes window position and size. That is exactly the cross-process control that the sandbox compatibility documentation excludes. Enabling `com.apple.security.app-sandbox` would therefore remove or destabilize the app's defining behavior, even if the person grants Accessibility in System Settings.

The App Store upload path also enforces sandboxing. App Review Guideline 2.4.5 further requires a self-contained app, consent before login launch, and Mac App Store-only updates. Guideline 2.5.1 requires public APIs to be used for their intended purposes. See [App Review Guidelines 2.4.5 and 2.5.1](https://developer.apple.com/app-store/review/guidelines/).

`AXUIElement` itself is public, and Apple documents `AXIsProcessTrustedWithOptions` as the supported way to check trust and asynchronously inform an untrusted user. That permission prompt does **not** override App Sandbox. See [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions) and [AXUIElementSetAttributeValue](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue).

### Could there be a reduced Store edition?

A sandboxed Store app could keep UI, settings, local layout calculations, and ScreenCaptureKit-based previews. It could not deliver SnapAssist's core promise of arranging arbitrary third-party windows through AX. Such a build would be a materially different product, not an equivalent distribution variant.

If commercial strategy still demands a Store presence, obtain written guidance for the exact App ID from Apple Developer Technical Support/App Review before spending engineering time. Do not add undocumented entitlements or temporary exceptions and do not plan a release around precedent inferred from other apps.

## Recommended direct-download release

Apple explicitly supports distributing macOS software outside the Mac App Store. For direct delivery:

- Sign the app and every executable it contains with a **Developer ID Application** certificate. A packaged installer, if used, needs **Developer ID Installer**. See [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).
- Enable **Hardened Runtime**. App Sandbox is optional for direct distribution, while Hardened Runtime is required for notarization. See [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution) and [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime).
- Include a secure timestamp and do not ship `com.apple.security.get-task-allow=true`. Use only the minimum Hardened Runtime exceptions actually required. See [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues).
- Submit the signed app/DMG/package through Xcode's Direct Distribution workflow or `xcrun notarytool`; `altool` is no longer accepted by the notary service. Staple the ticket to the app and final distributable where supported. See [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) and [Distributing your app for beta testing and releases](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases).
- Verify the exact artifact customers download, including its contained app, after stapling. Notarization is an automated malware and code-signing check, **not App Review**. See [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

The final gate should include at least:

```sh
codesign --verify --deep --strict --verbose=2 /path/to/SnapAssist.app
spctl --assess --type execute --verbose=4 /path/to/SnapAssist.app
xcrun stapler validate /path/to/SnapAssist.app
```

Also mount or extract a freshly downloaded copy and repeat the launch, Accessibility permission, Screen Recording permission, window-move, and thumbnail tests. A successful notarization request alone does not prove the shipped archive works.

### Identity stability

Keep one stable bundle identifier, Team ID, Developer ID certificate lineage, designated requirement, and installation location across direct releases. macOS uses the designated requirement to track access to privacy-protected resources; identity churn can therefore cause lost trust and another permission request. Apple also documents that default Mac App Store and Developer ID requirements are not mutually compatible, so the variants do not share privacy grants by default. See [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac) and [TN3127: Inside Code Signing: Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

If an experimental Mac App Store product is ever created, give it a separate bundle ID from the direct app. That prevents Store signing/sandbox identity from colliding with the direct product's TCC history and makes the feature difference explicit.

## ScreenCaptureKit and thumbnail privacy

ScreenCaptureKit is viable in both channel models, but Screen Recording is a separate permission from Accessibility. Apple requires the app to request permission before capture and to include a clear `NSScreenCaptureUsageDescription`. Apple recommends `SCContentSharingPicker` when users select capture sources. See [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) and [Capturing screen content in macOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos).

SnapAssist's automatic per-window thumbnail use does not map neatly to a system picker for every thumbnail. The safe product design is therefore:

- Make thumbnails an optional enhancement, off until the person chooses richer previews or explicitly approves them during onboarding.
- Keep the picker fully usable with application icons, names, and window titles when Screen Recording is denied.
- Explain that only visible-window snapshots are used, locally, for the picker.
- Keep captured frames in memory only, cancel outstanding work when the picker closes, and never transmit or persist them.
- Show a clear “Fenstervorschauen aktiv” state while capture-backed previews are in use. App Review Guideline 2.5.14 requires explicit consent and a clear visual and/or audible indication when recording or otherwise making a record of user activity: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
- Do not request persistent content capture; Apple documents that capability for VNC apps, not a transient window picker: [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit).

The current fallback concept is correct: Screen Recording must remain optional, while Accessibility is required for the snapping feature.

## Privacy manifest, privacy policy, and App Store disclosures

These are related but separate obligations:

1. **App privacy details:** App Store Connect requires accurate disclosures for data the app and incorporated third parties collect. Apple defines “collect” as transmitting data off-device in a way that makes it available beyond servicing the request; data processed only on-device is not collected for the label. If SnapAssist keeps titles, geometry, thumbnails, usage, and diagnostics on-device, its label can accurately state that those values are not collected. See [App privacy details](https://developer.apple.com/app-store/app-privacy-details/).
2. **Privacy policy:** App Review Guideline 5.1.1 requires every Store app to link its privacy policy in App Store Connect and in an easily accessible place inside the app, even if the policy says no data is collected. See [App Review Guidelines 5.1.1](https://developer.apple.com/app-store/review/guidelines/).
3. **Privacy manifest:** `PrivacyInfo.xcprivacy` describes collected-data practices on all supported platforms. Apple's required-reason API declaration requirement currently names iOS, iPadOS, tvOS, visionOS, and watchOS, not macOS. Listed third-party SDKs can independently require valid manifests and signatures. See [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) and [Third-party SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/).
4. **macOS bundle location:** When included in a Mac app, `PrivacyInfo.xcprivacy` belongs in `Contents/Resources/`. See [Adding a privacy manifest to your app or third-party SDK](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk).

A privacy manifest is not documented as a notarization prerequisite for a direct-only Mac app. Nevertheless, an explicit no-tracking/no-collection manifest and a short public privacy policy are advisable: they make the promise testable and prevent future SDK additions from silently changing it. The manifest must be truthful; a malformed or inaccurate manifest is worse than omitting an optional one.

## Current repository readiness

The following observations are from the checked-out repository on 2026-08-31, not from Apple documentation.

### Already aligned

- [`Resources/Info.plist`](../../Resources/Info.plist) declares `LSUIElement`, a stable-looking bundle ID (`com.caner.snapassist`), and a specific German `NSScreenCaptureUsageDescription`.
- [`Sources/SnapAssist/WindowSystem.swift`](../../Sources/SnapAssist/WindowSystem.swift) treats Accessibility and Screen Recording as separate permissions and uses `AXIsProcessTrustedWithOptions` for Accessibility onboarding.
- [`Sources/SnapAssist/ThumbnailProvider.swift`](../../Sources/SnapAssist/ThumbnailProvider.swift) uses `SCShareableContent`/`SCScreenshotManager`, performs no capture without preflight permission, keeps image results in memory, and returns an empty result for fallback when permission/capture fails.
- The product design already treats thumbnails as optional and window manipulation as Accessibility-dependent.

### Distribution blockers and gaps

| Severity | Repository finding | Required action |
|---|---|---|
| Blocker | [`scripts/build-app.sh`](../../scripts/build-app.sh) defaults to an Apple Development identity. | Add a release-only path requiring Developer ID Application; never silently fall back to development/ad hoc for public artifacts. |
| Blocker | The signing command does not enable Hardened Runtime or request a secure timestamp. | Sign release code with `--options runtime --timestamp`, then inspect the final entitlements/signature. |
| Blocker | There is no notarization, log check, stapling, or Gatekeeper assessment stage. | Add `notarytool`, fetch/check the notary log, staple, and validate the exact DMG/app shipped. |
| High | The release build is forced to `--arch arm64`. | Either document Apple-silicon-only support or produce and test a universal binary if Intel Macs on macOS 15 are in scope. This is a product-coverage decision, not an App Store rule. |
| Advisory | No `PrivacyInfo.xcprivacy` is bundled. With only Apple system frameworks and no macOS required-reason obligation identified, this is not currently a submission blocker. | Add a truthful manifest if data collection, tracking domains, or a manifest-requiring SDK is introduced; an explicit no-collection manifest may still be useful documentation. |
| High | No in-app privacy-policy access is visible in the menu-bar lifecycle. | Add a Privacy item and publish a stable HTTPS policy before Store submission; advisable for direct release too. |
| High | The ScreenCaptureKit purpose string is German only. | Localize permission copy for every shipped UI language and make the optional/fallback behavior explicit. |
| Medium | The picker silently falls back when thumbnail capture errors. | Preserve fallback, but expose a clear permission/status explanation and retry path instead of making the absence look broken. |
| Medium | The repository is a Swift package with a hand-assembled bundle and no release archive workflow. | Direct distribution can keep a scripted pipeline if it produces a valid signed/notarized artifact. For any Store experiment, add a reproducible Xcode/App Store Connect archive, validation, and upload workflow. |

There is currently no App Sandbox entitlement, which is correct for the recommended full-featured direct build. The absence is a Mac App Store blocker, but adding it would break the core capability rather than fix Store readiness.

## Build-variant recommendation

**Preferred:** maintain one public, unsandboxed direct-download build and make it the product of record.

If both channels are pursued despite the limitation, use distinct targets/schemes and bundle IDs rather than conditionally signing the same artifact after compilation:

| Concern | Direct target | Store target |
|---|---|---|
| Bundle ID | Stable direct ID | Separate Store ID |
| App Sandbox | Off | On, mandatory |
| Hardened Runtime | On | On |
| AX adapter | Included | Excluded; no claim of arbitrary window control |
| Thumbnail adapter | Optional, permission-gated | Optional, permission-gated |
| Updates/payment | Signed direct updater / direct commerce | Mac App Store only / StoreKit rules |
| Signing | Developer ID Application | App Store distribution signing/profile |
| Product messaging | Full window manager | Must accurately describe reduced, genuinely useful functionality |

Share pure layout and UI components, but do not ship AX code in the sandboxed target and merely hide it at runtime. That creates avoidable review ambiguity and a feature that can never pass its own acceptance tests.

## Release decision and gates

### Decision

Proceed with **notarized direct distribution**. Treat Mac App Store distribution as unsupported for the complete SnapAssist feature set unless Apple gives written approval for this exact app and entitlement model.

### Required direct-release gates

- Developer Program membership and Developer ID Application certificate are available.
- Release build is signed with Hardened Runtime, secure timestamp, no debug entitlement, and a stable identity.
- Notary result is accepted; log contains no unresolved signing warnings; ticket is stapled and validates offline.
- Final downloadable artifact passes `codesign`, `spctl`, install, launch, relaunch, update, and clean-machine tests.
- Accessibility onboarding, denial, later grant, revocation, and permission recovery are verified.
- Optional Screen Recording onboarding, denial, later grant, revocation, and icon-only fallback are verified.
- Captured images and window metadata remain ephemeral and on-device; privacy policy and manifest match actual behavior.
- Both Apple silicon and Intel are tested if both architectures are advertised.

### Only if a Store experiment is authorized

- Create a separate sandboxed target and App ID.
- Prove useful operation with all AX access removed before App Store Connect work begins.
- Use Xcode Archive/Validate and TestFlight for the exact distribution-signed build. Apple's distribution workflow uses separate App Store Connect and Direct Distribution methods: [Distributing your app for beta testing and releases](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases).
- Supply complete review notes explaining permission timing, ScreenCaptureKit behavior, data lifetime, and how to test every non-obvious feature.

## Primary Apple sources

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
- [Apple DTS: AX APIs are not supported in sandboxed apps](https://developer.apple.com/forums/thread/836644)
- [AXUIElement.h](https://developer.apple.com/documentation/applicationservices/axuielement_h)
- [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)
- [Capturing screen content in macOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
- [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
- [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Adding a privacy manifest](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
