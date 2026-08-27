# SnapAssist Implementation Plan

> **For agentic workers:** Execute inline with test-driven development and verify each checkpoint before continuing.

**Goal:** Ship a locally signed native macOS menu bar app that adds Windows-style Snap Assist and linked divider resizing to existing macOS/Raycast snapping.

**Architecture:** Pure geometry and layout state live in `SnapAssistCore` and are covered by unit tests. The `SnapAssist` executable adapts Accessibility, ScreenCaptureKit, AppKit panels, and global mouse monitoring to those pure models.

**Tech Stack:** Swift 6.3, Swift Package Manager, AppKit, SwiftUI, ApplicationServices, ScreenCaptureKit, XCTest.

## Global Constraints

- Target macOS 15 or later on Apple Silicon.
- No third-party dependencies and no private macOS APIs.
- App Sandbox disabled; Accessibility required, Screen Recording optional.
- Only currently visible Spaces participate.
- No persistent groups or settings window.

## Tasks

1. Create package structure and write failing tests for halves, thirds, quarters, gaps, occupancy, and non-matches.
2. Implement the smallest pure `SnapEngine` that passes those tests.
3. Write failing tests for shared divider detection, complete separator resizing, gaps, and minimum sizes; implement `DividerSolver`.
4. Write failing state tests for candidate filtering, layout groups, cooldown, and self-generated event suppression; implement the coordinator model.
5. Add the Accessibility window catalog, per-process observers, permission handling, frame mutation, activation, and visible-display normalization.
6. Add ScreenCaptureKit matching/capture and non-activating picker panels with mouse and keyboard input.
7. Add the passive mouse monitor and live linked resizing using the core divider solver.
8. Add the menu bar lifecycle, Info.plist, bundle script, ad-hoc signing, README, and acceptance checklist.
9. Run the complete unit suite, release build, bundle inspection, launch smoke test, and git diff review.

