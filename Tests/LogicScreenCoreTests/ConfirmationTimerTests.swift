import XCTest
@testable import LogicScreenCore

final class ConfirmationTimerTests: XCTestCase {
    @MainActor
    func testExpiryCanCancelTimerWithoutCancellingAsyncRestoration() async {
        let timer = ConfirmationTimer()
        let restored = expectation(description: "Recovery completes after its suspension")
        var completed = false
        timer.start(duration: 0.01, tick: { _ in }, expired: {
            timer.cancel() // Same path used by the restore button and timeout recovery.
            do {
                try await Task.sleep(for: .milliseconds(1))
                completed = true
            } catch { XCTFail("Recovery inherited cancellation from its own timer") }
            restored.fulfill()
        })
        await fulfillment(of: [restored], timeout: 2)
        XCTAssertTrue(completed)
    }

    @MainActor
    func testReplacementCancelsThePreviousExpiry() async {
        let timer = ConfirmationTimer()
        let expired = expectation(description: "New confirmation expires")
        var oldCallbackRan = false
        var seconds: [Int] = []
        timer.start(duration: 0.01, tick: { _ in }, expired: { oldCallbackRan = true })
        timer.start(duration: 0.01, tick: { seconds.append($0) }, expired: { expired.fulfill() })
        await fulfillment(of: [expired], timeout: 2)
        XCTAssertFalse(oldCallbackRan)
        XCTAssertEqual(seconds.first, 1)
        XCTAssertEqual(seconds.last, 0)
    }
}
