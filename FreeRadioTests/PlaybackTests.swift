import XCTest
@testable import FreeRadio

final class PlaybackTests: XCTestCase {
    func testRetryBudgetStopsAtThirtySeconds() {
        let policy = PlaybackRetryPolicy(startedAt: 100)

        XCTAssertTrue(policy.shouldRetry(at: 100))
        XCTAssertTrue(policy.shouldRetry(at: 129.99))
        XCTAssertFalse(policy.shouldRetry(at: 130))
        XCTAssertFalse(policy.shouldRetry(at: 131))
    }

    func testRetryDelayBacksOffAndCapsAtEightSeconds() {
        let policy = PlaybackRetryPolicy(startedAt: 0)

        XCTAssertEqual(policy.nextDelay(after: 1), 2)
        XCTAssertEqual(policy.nextDelay(after: 2), 4)
        XCTAssertEqual(policy.nextDelay(after: 4), 8)
        XCTAssertEqual(policy.nextDelay(after: 8), 8)
    }

    func testObsoleteOrUserCancelledEventsCannotResumePlayback() {
        XCTAssertTrue(PlaybackEventPolicy.accepts(generation: 4, currentGeneration: 4,
                                                   explicitlyStopped: false, state: .reconnecting))
        XCTAssertFalse(PlaybackEventPolicy.accepts(generation: 3, currentGeneration: 4,
                                                    explicitlyStopped: false, state: .reconnecting))
        XCTAssertFalse(PlaybackEventPolicy.accepts(generation: 4, currentGeneration: 4,
                                                    explicitlyStopped: true, state: .reconnecting))
        XCTAssertFalse(PlaybackEventPolicy.accepts(generation: 4, currentGeneration: 4,
                                                    explicitlyStopped: false, state: .paused))
        XCTAssertFalse(PlaybackEventPolicy.accepts(generation: 4, currentGeneration: 4,
                                                    explicitlyStopped: false, state: .stopped))
    }

    func testOnlyLiveStatesAreActive() {
        XCTAssertTrue(PlaybackState.loading.isActive)
        XCTAssertTrue(PlaybackState.playing.isActive)
        XCTAssertTrue(PlaybackState.reconnecting.isActive)
        XCTAssertFalse(PlaybackState.idle.isActive)
        XCTAssertFalse(PlaybackState.paused.isActive)
        XCTAssertFalse(PlaybackState.stopped.isActive)
        XCTAssertFalse(PlaybackState.failed.isActive)
    }
}
