import XCTest
@testable import AppLockerCore

final class WindowVisibilityTests: XCTestCase {
    func testCatalystEmptyAccessibilityListCannotBypassVisibleWindow() {
        XCTAssertTrue(WindowVisibility.shouldIntercept(explicitOpen: false, accessibilityWindowCount: 0, visibleWindowCount: 1))
    }
    func testExplicitOpenAlwaysRequiresAuthenticationEvenBeforeWindowIsPublished() {
        XCTAssertTrue(WindowVisibility.shouldIntercept(explicitOpen: true, accessibilityWindowCount: 0, visibleWindowCount: 0))
    }
    func testClosingLastWindowDoesNotPromptUntilReopen() {
        XCTAssertFalse(WindowVisibility.shouldIntercept(explicitOpen: false, accessibilityWindowCount: 0, visibleWindowCount: 0))
    }
    func testUnavailableAPIsDoNotGrantAccess() {
        XCTAssertTrue(WindowVisibility.shouldIntercept(explicitOpen: false, accessibilityWindowCount: nil, visibleWindowCount: nil))
    }
    func testAccessibilityVisibleWindowStillTriggersProtectionOffCurrentSpace() {
        XCTAssertTrue(WindowVisibility.shouldIntercept(explicitOpen: false, accessibilityWindowCount: 1, visibleWindowCount: 0))
    }
}
