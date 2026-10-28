import XCTest
@testable import FreeRadio

final class ICYMetadataTests: XCTestCase {
    private func stream(audio: Int, metadata: String, metaInterval: Int) -> [UInt8] {
        var block = Array(metadata.utf8)
        let blocks = (block.count + 15) / 16
        block += Array(repeating: 0, count: blocks * 16 - block.count)
        return Array(repeating: 0xFF, count: audio) + [UInt8(blocks)] + block
    }

    func testReadsStreamTitleAfterMetaInterval() {
        var reader = ICYMetadataReader(metaInterval: 32)
        let bytes = stream(audio: 32, metadata: "StreamTitle='Artist A - Song B';StreamUrl='';", metaInterval: 32)

        let titles = bytes.compactMap { reader.consume($0) }

        XCTAssertEqual(titles, ["Artist A - Song B"])
    }

    func testSkipsEmptyBlocksUntilTitleArrives() {
        var reader = ICYMetadataReader(metaInterval: 8)
        let bytes = Array(repeating: UInt8(0xFF), count: 8) + [0]
            + stream(audio: 8, metadata: "StreamTitle='Second';", metaInterval: 8)

        XCTAssertEqual(bytes.compactMap { reader.consume($0) }, ["Second"])
    }

    func testPlaceholderTitleAtConnectionStartIsReplacedByNextTitle() {
        var reader = ICYMetadataReader(metaInterval: 8)
        let bytes = stream(audio: 8, metadata: "StreamTitle='THIS STATION WILL CONTINUE AFTER THIS BREAK';", metaInterval: 8)
            + stream(audio: 8, metadata: "StreamTitle='Artist A - Song B';", metaInterval: 8)

        for byte in bytes { _ = reader.consume(byte) }

        XCTAssertEqual(reader.settledTitle, "Artist A - Song B")
    }

    func testTitleSettlesAfterFollowingEmptySlot() {
        var reader = ICYMetadataReader(metaInterval: 8)
        let first = stream(audio: 8, metadata: "StreamTitle='Only Title';", metaInterval: 8)
        for byte in first { _ = reader.consume(byte) }
        XCTAssertNil(reader.settledTitle)

        for byte in Array(repeating: UInt8(0xFF), count: 8) + [0] { _ = reader.consume(byte) }
        XCTAssertEqual(reader.settledTitle, "Only Title")
    }

    func testTitleMayContainApostrophes() {
        XCTAssertEqual(ICYMetadataReader.streamTitle(in: Data("StreamTitle='Artist - Don't Stop';".utf8)),
                       "Artist - Don't Stop")
    }

    func testFallsBackToLatin1WhenNotUTF8() {
        let latin1 = "StreamTitle='Beyoncé - Song';".data(using: .isoLatin1)!
        XCTAssertEqual(ICYMetadataReader.streamTitle(in: latin1), "Beyoncé - Song")
    }

    func testBlankOrMissingTitleIsNil() {
        XCTAssertNil(ICYMetadataReader.streamTitle(in: Data("StreamTitle='';".utf8)))
        XCTAssertNil(ICYMetadataReader.streamTitle(in: Data("StreamUrl='https://example.com';".utf8)))
    }

    func testOnlyProgressiveStreamsArePolled() {
        XCTAssertTrue(ICYTitlePoller.supports(URL(string: "https://example.com/stream")!))
        XCTAssertTrue(ICYTitlePoller.supports(URL(string: "http://example.com/live.mp3")!))
        XCTAssertFalse(ICYTitlePoller.supports(URL(string: "https://example.com/live/playlist.m3u8")!))
    }
}
