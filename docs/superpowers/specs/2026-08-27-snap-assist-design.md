# SnapAssist Design

## Goal

Build a native, dependency-free macOS menu bar application that detects window snaps performed by macOS or tools such as Raycast, then offers visible windows for every empty slot in the detected layout.

## Supported layouts

- Left and right halves.
- Three vertical thirds, including windows spanning two adjacent thirds.
- Four corner quarters in a 2x2 grid.

Only the visible Spaces on all connected displays participate. Hidden Spaces, minimized windows, system windows, and windows that cannot be moved or resized are excluded.

## Snap assist

Accessibility notifications trigger passive geometry detection after a move or resize completes. A 24-point tolerance permits normal macOS and Raycast gaps. Existing windows occupying layout slots are retained; each empty slot gets a non-activating picker panel.

The picker displays ScreenCaptureKit window thumbnails when Screen Recording permission is available and falls back to application icons and titles otherwise. Mouse clicks select directly. Tab changes the target slot, arrow keys change the selected candidate, Return confirms, and Escape or an outside click cancels.

## Linked resizing

Windows that partition a recognized layout form an in-memory group. When the pointer grabs a shared divider, a passive global mouse monitor observes the drag. The divider delta is propagated to every window touching the same separator, preserving outer edges and gaps. Minimum sizes and frames rejected by an application clamp the divider.

Groups are reconstructed after recognized snaps and discarded when their windows close, minimize, move to another display, or leave the layout.

## Permissions and lifecycle

Accessibility permission is required for window discovery and manipulation. Without it, SnapAssist remains paused and exposes a permission action in the menu. Screen Recording permission is optional and controls thumbnails only.

SnapAssist is an LSUIElement menu bar app with no Dock icon and no settings window. Its menu contains Active/Pause, permission status/actions, and Quit. State is not persisted across launches.

## Delivery

The repository contains a Swift package, automated tests, a reproducible bundling script, and a locally ad-hoc-signed Apple Silicon `SnapAssist.app`. App Store distribution and notarization are out of scope.

