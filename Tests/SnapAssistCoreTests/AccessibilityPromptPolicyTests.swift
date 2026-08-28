import XCTest
@testable import SnapAssistCore

final class AccessibilityPromptPolicyTests: XCTestCase {
    func testRequestsPermissionOnlyOnFirstUntrustedLaunch() {
        XCTAssertTrue(AccessibilityPromptPolicy.shouldPrompt(
            isTrusted: false,
            hasRequestedBefore: false
        ))
        XCTAssertFalse(AccessibilityPromptPolicy.shouldPrompt(
            isTrusted: false,
            hasRequestedBefore: true
        ))
    }

    func testNeverRequestsPermissionWhenAlreadyTrusted() {
        XCTAssertFalse(AccessibilityPromptPolicy.shouldPrompt(
            isTrusted: true,
            hasRequestedBefore: false
        ))
    }
}

