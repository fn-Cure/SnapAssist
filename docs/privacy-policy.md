# SnapAssist Privacy Policy

Last updated: 2026-08-31

SnapAssist is a native macOS window-management utility. It does not contain advertising, analytics, telemetry, tracking, or third-party SDKs, and it does not transmit information off the Mac.

## Information processed locally

To provide its window picker and layout behavior, SnapAssist temporarily processes:

- application names and window titles;
- window positions, sizes, and display identifiers;
- optional window preview images when Screen Recording permission is granted;
- local diagnostic status such as Accessibility observer failures and the last window-placement error.

This information remains on the Mac. Window preview images are kept in memory only and are discarded when the picker closes or its session becomes invalid. SnapAssist does not create a history of windows or previews.

## Permissions

Accessibility permission is required to discover, focus, move, and resize windows. Screen Recording permission is optional and is used only for local preview images; the picker remains usable with application icons and titles when this permission is denied.

Both permissions can be revoked at any time in macOS System Settings. Revoking Accessibility pauses window-management functionality. Revoking Screen Recording disables previews but does not disable the picker.

## Data collection and sharing

SnapAssist does not collect, sell, share, or transmit personal data. It has no network client and no user account system.

## Changes

If a future version introduces networking, analytics, third-party SDKs, or persistent storage of window information, this policy and the app's privacy manifest must be updated before release.

## Publisher contact

The canonical HTTPS copy is published with the source repository at <https://github.com/fn-Cure/SnapAssist/blob/main/docs/privacy-policy.md>. Questions and support requests can be submitted at <https://github.com/fn-Cure/SnapAssist/issues>.
