import XCTest
@testable import LogicScreenCore

final class WindowInventoryTests: XCTestCase {
    func testPreflightOnlyCountsWindowsOnScreensBeingDisabled() {
        let inventory = WindowInventory(windows: [
            WindowPreview(applicationPID: 1, displayID: "source"),
            WindowPreview(applicationPID: 1, displayID: "source", restriction: .fullScreen),
            WindowPreview(applicationPID: 2, displayID: "target", restriction: .minimized),
            WindowPreview(applicationPID: 3, displayID: "other", restriction: .fixed)
        ])
        let result = inventory.readiness(sourceIDs: ["source"])
        XCTAssertEqual(result.movable, 1)
        XCTAssertEqual(result.blocked, 1)
        XCTAssertFalse(result.canProceed)
    }

    func testSpecialWindowsOnRetainedScreenDoNotBlockMigration() {
        let inventory = WindowInventory(windows: [
            WindowPreview(applicationPID: 1, displayID: "source"),
            WindowPreview(applicationPID: 2, displayID: "target", restriction: .fullScreen)
        ])
        XCTAssertTrue(inventory.readiness(sourceIDs: ["source"]).canProceed)
    }

    func testUnreadableApplicationBlocksEvenWhenNoSourceWindowsAreKnown() {
        let inventory = WindowInventory(unreadablePIDs: [99])
        let result = inventory.readiness(sourceIDs: ["source"])
        XCTAssertEqual(result.movable, 0)
        XCTAssertEqual(result.unreadableApplications, 1)
        XCTAssertFalse(result.canProceed)
    }

    func testMultipleSourceScreensAreCheckedTogether() {
        let inventory = WindowInventory(windows: [
            WindowPreview(applicationPID: 1, displayID: "first"),
            WindowPreview(applicationPID: 2, displayID: "second"),
            WindowPreview(applicationPID: 2, displayID: "second", restriction: .minimized)
        ])
        let result = inventory.readiness(sourceIDs: ["first", "second"])
        XCTAssertEqual(result.movable, 2)
        XCTAssertEqual(result.blocked, 1)
        XCTAssertFalse(result.canProceed)
    }

    func testEmptyReadableDesktopCanProceedToFreshVerification() {
        XCTAssertTrue(WindowInventory().readiness(sourceIDs: ["source"]).canProceed)
    }
}
