import XCTest
@testable import AppLockerCore

final class LockSessionTests: XCTestCase {
    let whatsapp = ProcessIdentity(pid: 101, launchedAt: Date(timeIntervalSince1970: 1))
    let other = ProcessIdentity(pid: 202, launchedAt: Date(timeIntervalSince1970: 2))

    func testRapidReopenSameProcessRequiresFreshAuthentication() {
        var session = LockSession()
        let request = session.begin(whatsapp)!
        XCTAssertTrue(session.finish(request, process: whatsapp, success: true))
        XCTAssertTrue(session.allows(whatsapp))
        session.revoke(whatsapp) // switch away, close last window, hide, or minimize
        XCTAssertFalse(session.allows(whatsapp))
        XCTAssertNotNil(session.begin(whatsapp)) // no 2–3 second exemption
    }

    func testDuplicateNotificationsDoNotCreateConcurrentPrompts() {
        var session = LockSession()
        XCTAssertNotNil(session.begin(whatsapp))
        XCTAssertNil(session.begin(whatsapp))
        XCTAssertNil(session.begin(other))
        XCTAssertFalse(session.allows(other))
    }

    func testCancellationDoesNotUnlockAndAllowsRetry() {
        var session = LockSession()
        let request = session.begin(whatsapp)!
        XCTAssertTrue(session.finish(request, process: whatsapp, success: false))
        XCTAssertFalse(session.allows(whatsapp))
        XCTAssertNotNil(session.begin(whatsapp))
    }

    func testStaleSuccessAfterSleepOrTerminationCannotUnlock() {
        var session = LockSession()
        let stale = session.begin(whatsapp)!
        session.revoke()
        let fresh = session.begin(whatsapp)!
        XCTAssertFalse(session.finish(stale, process: whatsapp, success: true))
        XCTAssertFalse(session.allows(whatsapp))
        XCTAssertTrue(session.finish(fresh, process: whatsapp, success: true))
    }

    func testReusedPIDDoesNotInheritAnUnlock() {
        var session = LockSession()
        let request = session.begin(whatsapp)!
        session.finish(request, process: whatsapp, success: true)
        let replacement = ProcessIdentity(pid: whatsapp.pid, launchedAt: Date(timeIntervalSince1970: 99))
        XCTAssertFalse(session.allows(replacement))
        session.revoke(other) // late termination from an unrelated process
        XCTAssertTrue(session.allows(whatsapp))
    }

    func testSuccessIsBoundToTheRequestedProcess() {
        var session = LockSession()
        let request = session.begin(whatsapp)!
        XCTAssertFalse(session.finish(request, process: other, success: true))
        XCTAssertFalse(session.allows(other))
        XCTAssertFalse(session.allows(whatsapp))
    }
}
