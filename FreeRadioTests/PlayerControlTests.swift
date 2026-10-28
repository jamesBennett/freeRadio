import XCTest
@testable import FreeRadio

final class PlayerControlTests: XCTestCase {
    func testTransportStopsLiveStatesAndPlaysOthers() {
        XCTAssertEqual(TransportAction(state: .playing), .stop)
        XCTAssertEqual(TransportAction(state: .loading), .stop)
        XCTAssertEqual(TransportAction(state: .reconnecting), .stop)
        XCTAssertEqual(TransportAction(state: .paused), .play)
        XCTAssertEqual(TransportAction(state: .stopped), .play)
        XCTAssertEqual(TransportAction(state: .failed), .play)
        XCTAssertEqual(TransportAction(state: .idle), .play)
    }

    func testHorizontalSwipeReturnsToStations() {
        XCTAssertTrue(PlayerSwipe.returnsToStations(translation: CGSize(width: -120, height: 10)))
        XCTAssertTrue(PlayerSwipe.returnsToStations(translation: CGSize(width: 120, height: -10)))
    }

    func testShortFastFlickReturnsToStations() {
        XCTAssertTrue(PlayerSwipe.returnsToStations(translation: CGSize(width: -45, height: 5),
                                                    predictedEnd: CGSize(width: -260, height: 20)))
    }

    func testShortOrVerticalDragsDoNotNavigate() {
        XCTAssertFalse(PlayerSwipe.returnsToStations(translation: CGSize(width: -40, height: 0),
                                                     predictedEnd: CGSize(width: -60, height: 0)))
        XCTAssertFalse(PlayerSwipe.returnsToStations(translation: CGSize(width: -120, height: 150)))
    }
}
