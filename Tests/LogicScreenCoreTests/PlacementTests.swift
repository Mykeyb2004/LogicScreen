import XCTest
import CoreGraphics
@testable import LogicScreenCore

final class PlacementTests: XCTestCase {
    func testMovingFromLeftScreenPreservesRelativePosition() {
        let source = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        let target = CGRect(x: 0, y: 30, width: 2048, height: 1060)
        let window = CGRect(x: -960, y: 540, width: 960, height: 740)
        let moved = WindowPlacement.movedFrame(window, from: source, to: target, canResize: true)
        XCTAssertEqual(moved.maxX, target.maxX)
        XCTAssertEqual(moved.maxY, target.maxY)
        XCTAssertEqual(moved.size, window.size)
    }

    func testOversizedWindowFitsSmallerScreen() {
        let target = CGRect(x: -1000, y: -800, width: 1000, height: 760)
        let moved = WindowPlacement.movedFrame(CGRect(x: 0, y: 0, width: 2200, height: 1500),
                                               from: CGRect(x: 0, y: 0, width: 2560, height: 1600),
                                               to: target, canResize: true)
        XCTAssertEqual(moved, target)
    }

    func testFixedSizeWindowKeepsItsTitleBarReachable() {
        let moved = WindowPlacement.movedFrame(CGRect(x: -1400, y: 800, width: 1600, height: 1200),
                                               from: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                                               to: CGRect(x: 0, y: 30, width: 1000, height: 700), canResize: false)
        XCTAssertEqual(moved.origin, CGPoint(x: 0, y: 30))
        XCTAssertEqual(moved.size, CGSize(width: 1600, height: 1200))
    }

    func testOffscreenWindowClampsToDestination() {
        let target = CGRect(x: 0, y: 30, width: 1200, height: 800)
        let moved = WindowPlacement.movedFrame(CGRect(x: -9999, y: 9999, width: 600, height: 400),
                                               from: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                                               to: target, canResize: true)
        XCTAssertTrue(target.contains(moved))
    }

    func testAppKitCoordinateConversionHandlesScreenAboveMain() {
        let converted = WindowPlacement.appKitToQuartz(CGRect(x: -100, y: 1200, width: 800, height: 600), mainDisplayHeight: 1152)
        XCTAssertEqual(converted, CGRect(x: -100, y: -648, width: 800, height: 600))
    }

    func testWindowOnBoundaryBelongsToScreenWithLargestIntersection() {
        let left = display("left", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        let right = display("right", frame: CGRect(x: 0, y: 0, width: 2048, height: 1152))
        let owner = WindowPlacement.owningDisplay(for: CGRect(x: -100, y: 100, width: 600, height: 500), displays: [left, right])
        XCTAssertEqual(owner?.id, "right")
    }

    func testCannotDisconnectLastScreen() {
        XCTAssertThrowsError(try DisplaySafety.validateDisconnection(ids: ["only"], displays: [display("only")]))
    }

    func testCannotDisconnectEveryScreenTogether() {
        XCTAssertThrowsError(try DisplaySafety.validateDisconnection(ids: ["a", "b"], displays: [display("a"), display("b")]))
    }

    func testCannotUseStaleScreenIdentity() {
        XCTAssertThrowsError(try DisplaySafety.validateDisconnection(ids: ["stale"], displays: [display("a"), display("b")]))
    }

    func testCanDisconnectSecondaryAndKeepMain() {
        XCTAssertNoThrow(try DisplaySafety.validateDisconnection(ids: ["b"], displays: [display("a"), display("b")]))
    }

    func testDisplaySnapshotRoundTripRetainsNegativeCoordinatesAndIdentity() throws {
        let original = display("stable-uuid", frame: CGRect(x: -1920, y: -1080, width: 1920, height: 1080))
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(DisplayRecord.self, from: data), original)
    }

    private func display(_ id: String, frame: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)) -> DisplayRecord {
        DisplayRecord(id: id, displayID: 1, name: id, frame: frame, visibleFrame: frame,
                      isMain: id == "a", isBuiltIn: false, isActive: true)
    }
}
