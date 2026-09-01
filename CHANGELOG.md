# Changelog

All notable user-facing changes to SnapAssist are documented here.

## 0.3.7 — 2026-09-01

### Fixed

- Deferred creation of the menu-bar status item until AppKit finishes its initial FrontBoard scene layout, eliminating an intermittent first-launch layout-recursion warning on macOS 26.
- Kept first-run onboarding responsive by scheduling it independently from the delayed status item.

## 0.3.6 — 2026-09-01

### Improved

- Cached Accessibility and Screen Recording status between the single two-second permission checks instead of issuing duplicate TCC requests from both the runtime and Settings model.
- Reduced background Service Management status refreshes from once per second to once every two seconds.

## 0.3.5 — 2026-09-01

### Fixed

- Strengthened rollback for Chromium and other applications that process cross-display position and size changes in separate phases.
- Rollback now tries both AX write orders, verifies the restored frame after each attempt, and reports the actual final frame when an application still refuses part of the restoration.

## 0.3.4 — 2026-09-01

### Added

- Native onboarding and Settings for general behavior, permissions, diagnostics, privacy, and app information.
- Optional launch at login through the macOS Service Management API.
- Icon-and-title fallback when Screen Recording permission is unavailable.
- In-memory diagnostics that can be copied from Settings without sending data anywhere.
- Public Core Graphics geometry fallback for applications that omit or delay Accessibility move/resize notifications.
- Universal Apple silicon and Intel build, Hardened Runtime signing, privacy manifest, localized permission text, and direct-release verification scripts.

### Improved

- Picker zones and candidate cards now expose distinct VoiceOver window, button, value, selected-state, and target-hint semantics.
- Candidate previews appear asynchronously so the picker stays responsive while thumbnails are generated.
- Enabled and experimental linked-resize choices persist across launches.
- Pausing SnapAssist now suspends Accessibility observers, retries, and geometry polling instead of merely ignoring their events.
- The package now builds in Swift 6.3 language mode with explicit Window and Thumbnail adapter protocols.

### Fixed

- Prevented repeated Return presses or clicks from starting overlapping window placements.
- Matched Accessibility, Core Graphics, and ScreenCaptureKit windows with stable `(PID, CGWindowID)` identity, including identically titled windows.
- Added bounded alternative AX write orders, frame read-back, and rollback when an application delays, clamps, or refuses a move or resize.
- Prevented stale picker sessions from committing a placement after the layout changed.
- Cleared all in-memory thumbnails when the picker closes, a placement completes, or Screen Recording permission changes.
- Recovered from stale Accessibility observer elements and applications with incomplete observer support.

### Distribution note

The complete SnapAssist product is distributed directly outside the Mac App Store. Its cross-application Accessibility control is incompatible with the App Sandbox required for new Mac App Store apps. Public direct releases require Developer ID signing, notarization, public support/privacy pages, and a stable update channel.
