# SnapAssist Release Checklist

Use this checklist for the exact DMG that will be published. A local development build or an accepted notarization request alone is not a release.

## Automated preflight

- [x] Swift 6.3 package in Swift 6 language mode.
- [x] `swift test` passes all 40 tests.
- [x] Universal release build contains `arm64` and `x86_64`.
- [x] `Info.plist`, localized purpose strings, privacy manifest, and shell scripts validate locally.
- [x] Development app passes strict code-signature verification and uses Hardened Runtime.
- [ ] GitHub Actions check is green on the pull request. The prepared workflow cannot be pushed until the GitHub credential has `workflow` scope.

## Product acceptance

- [x] Accessibility permission is requested only after an explicit action and later grants are detected without repeated prompting.
- [x] Screen Recording remains optional; icon/title cards work without it.
- [x] Picker zones and candidate cards expose distinct VoiceOver semantics.
- [x] A second mouse or keyboard confirmation cannot overlap an active placement.
- [x] A deliberately oversized fixture window is clamped by AppKit and returns to its exact verified original frame through the dual-order rollback.
- [x] Enabled and experimental-resize choices persist; Paused suspends AX observation and geometry polling.
- [ ] Reproduce the previously failing target application and confirm the selected window reaches the requested free zone instead of overlapping the trigger window.
- [x] Controlled Finder and Safari windows are selected through real picker `AXPress` actions and reach the exact requested quarter in one verified attempt.
- [ ] One Chromium/Electron app passes placement after the 0.3.5 rollback fix, plus Return, Escape, close, minimize, and refused/minimum-size cases.
- [ ] Internal and external displays pass half, thirds, quarters, cross-display candidate placement, and disconnect recovery.
- [ ] Screen Recording denial, later grant, revocation, and icon-only fallback pass in a clean user account.
- [ ] Accessibility denial, later grant, revocation, relaunch, and TCC identity retention pass in a clean user account.
- [x] Version 0.3.7 completes a continuous 1,804-second idle run with 359 samples, 0.27% average CPU including launch, no error/fault logs, and no orphan picker panels.
- [ ] Multi-hour mixed-application soak completes without stale panels, wrong-zone placement, or orphan state.

## Public direct release

- [ ] Developer ID Application certificate is installed and its stable identity is recorded.
- [ ] A `notarytool` keychain profile is configured.
- [ ] Stable public HTTPS download page, privacy-policy URL, support contact, and update policy exist.
- [ ] Repository license and public/private repository decision are explicit.
- [ ] `SNAPASSIST_NOTARY_PROFILE=<profile> scripts/package-release.sh` succeeds.
- [ ] App notary result and DMG notary result both say `Accepted`; rejection logs contain no unresolved issue.
- [ ] App and DMG tickets staple and validate.
- [ ] `scripts/verify-release.sh outputs/release/SnapAssist.dmg` mounts the DMG and verifies the contained app.
- [ ] A freshly downloaded copy installs, launches, relaunches, receives permissions, displays thumbnails/fallback, and places windows on a clean Mac or clean account.
- [ ] SHA-256 checksum, versioned release notes, minimum macOS version, supported architectures, and installation instructions are published beside the DMG.

## Mac App Store boundary

The complete product is not submitted to the Mac App Store: mandatory App Sandbox does not support its cross-application Accessibility control. A Store experiment requires a separate bundle identifier, sandboxed target, reduced product specification, and written Apple guidance before implementation.
