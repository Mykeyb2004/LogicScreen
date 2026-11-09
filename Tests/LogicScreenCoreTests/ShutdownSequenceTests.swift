import XCTest
@testable import LogicScreenCore

final class ShutdownSequenceTests: XCTestCase {
    func testFailedWindowMigrationNeverTurnsOffScreen() async {
        var disconnected = false
        do {
            _ = try await ScreenShutdownSequence.perform(migrate: { MigrationReport(moved: 2, failed: 1) },
                                                          verify: { XCTFail("Must stop before verification"); return true },
                                                          disconnect: { disconnected = true })
            XCTFail("Expected migration failure")
        } catch {}
        XCTAssertFalse(disconnected)
    }

    func testFullscreenOrMinimizedWindowOnSourcePreventsShutdown() async {
        var disconnected = false
        do {
            _ = try await ScreenShutdownSequence.perform(migrate: { MigrationReport(blocked: 1) },
                                                          verify: { true }, disconnect: { disconnected = true })
            XCTFail("Expected blocked window")
        } catch {}
        XCTAssertFalse(disconnected)
    }

    func testWindowAppearingAfterMigrationPreventsShutdown() async {
        var disconnected = false
        do {
            _ = try await ScreenShutdownSequence.perform(migrate: { MigrationReport(moved: 3) },
                                                          verify: { false }, disconnect: { disconnected = true })
            XCTFail("Expected fresh inventory failure")
        } catch {}
        XCTAssertFalse(disconnected)
    }

    func testSuccessfulMigrationIsVerifiedBeforeShutdown() async throws {
        var migrated = false
        var verified = false
        var disconnected = false
        let result = try await ScreenShutdownSequence.perform(migrate: {
            XCTAssertFalse(disconnected)
            migrated = true
            return MigrationReport(moved: 4)
        }, verify: {
            XCTAssertTrue(migrated)
            XCTAssertFalse(disconnected)
            verified = true
            return true
        }, disconnect: {
            XCTAssertTrue(migrated)
            XCTAssertTrue(verified)
            disconnected = true
        })
        XCTAssertTrue(disconnected)
        XCTAssertEqual(result.moved, 4)
    }

    func testUnreadableApplicationPreventsShutdown() async {
        var disconnected = false
        do {
            _ = try await ScreenShutdownSequence.perform(migrate: { MigrationReport(unreadableApplications: 1) },
                                                          verify: { true }, disconnect: { disconnected = true })
            XCTFail("Expected unreadable application failure")
        } catch {}
        XCTAssertFalse(disconnected)
    }
}
