# SnapAssist End-User Product Specification

**Status:** Active specification for SnapAssist 0.3.x and later.  
**Supersedes:** The lifecycle, settings, persistence, architecture scope, and delivery constraints in `docs/superpowers/specs/2026-08-27-snap-assist-design.md`. The original layout and interaction requirements remain valid unless changed here.

## Product promise

SnapAssist is a native macOS menu-bar utility for people familiar with Windows Snap Assist. After another tool or macOS places a window into a supported half, third, or quarter layout, SnapAssist displays the eligible windows that can fill each remaining zone and places exactly one selected window into the selected free zone.

The app must be understandable without developer knowledge, remain useful without window thumbnails, and fail without leaving a selected window in a partially moved state.

## Supported behavior

- Detect left and right halves, vertical single and double thirds, and four corner quarters on every currently visible display Space.
- Treat a picker selection as one atomic operation. While placement is pending, mouse and keyboard confirmation are disabled and a second placement cannot start.
- Verify the destination frame after every Accessibility mutation. Retry bounded alternative write orders; if the destination cannot be verified, restore and verify the original frame.
- Never commit a layout group from an unverified frame or a picker session that changed during placement.
- Detect geometry changes through Accessibility observers and a low-frequency public Core Graphics metadata fallback for applications that omit or delay AX notifications.
- Keep linked divider resizing explicitly labelled experimental until cross-application soak tests pass.

## End-user experience

- Run as a menu-bar app without a Dock icon.
- Provide native onboarding for Accessibility, optional Screen Recording, and completion status.
- Provide Settings for General, Permissions, About, and Privacy.
- Persist user choices such as onboarding completion, enabled state, login-item choice, and experimental-feature choice.
- Support mouse, Tab, arrow keys, Return, Escape, VoiceOver labels and hints, Increased Contrast, and Reduce Motion.
- Display an in-context progress state during placement and a specific recoverable error when an application refuses or clamps the requested frame.
- Display “Fenstervorschauen aktiv” whenever ScreenCaptureKit images are present. Without Screen Recording, show app icons, app names, and window titles.

## Privacy and permissions

- Accessibility is required only for discovering and arranging third-party windows. Permission must be requested from a deliberate user action, not repeatedly at launch.
- Screen Recording is optional. Snapshots are generated only for visible picker candidates, retained in memory only for the active picker lifecycle, and cleared on cancellation, placement, permission change, or invalidation.
- No window title, geometry, snapshot, diagnostic event, or usage data is transmitted or persisted.
- The in-app privacy statement, bundled privacy manifest, permission purpose strings, and public privacy policy must describe the same behavior.

## Distribution

The complete product is an unsandboxed direct-download macOS app. It must be Universal (`arm64` and `x86_64`), signed with Developer ID Application, use Hardened Runtime and a secure timestamp, and be notarized and stapled as both the contained app and final DMG.

The exact mounted DMG and contained app must pass signature, Gatekeeper, architecture, identifier, version, and stapling checks. A release is not accepted until the installed artifact has passed launch, relaunch, permission grant/revocation, picker placement, and fallback tests on a clean user account or clean Mac.

The full feature set is not a supported Mac App Store target because App Sandbox is mandatory there and does not support this cross-application Accessibility control. Any Store edition would be a separate, reduced product with a separate bundle identifier and specification.

## External release requirements

- Stable HTTPS download location.
- Stable HTTPS privacy-policy URL and a public support contact.
- Developer ID Application certificate and configured `notarytool` keychain profile.
- A documented update mechanism or an explicit first-release policy that tells users how updates are discovered and installed.

## Acceptance gates

- All unit and state-machine tests pass with no warnings.
- No duplicate mouse or keyboard confirmation can overlap a placement.
- Failed or cancelled placement leaves the window at its verified original frame.
- Identically titled windows remain distinct through `(PID, CGWindowID)` identity.
- Picker and fallback detection work on internal and external displays with Finder, Safari, and a Chromium/Electron application.
- Screen Recording denial and revocation immediately remove in-memory thumbnails while icon/title selection remains available.
- A 30-minute idle run remains low CPU, and a multi-hour mixed-app soak produces no stale picker, orphan panel, or wrong-zone placement.
- The downloadable notarized DMG, not merely a local build directory, passes the release verification script and manual clean-install checklist.
