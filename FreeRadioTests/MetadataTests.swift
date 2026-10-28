import Foundation
import XCTest
@testable import FreeRadio

final class MetadataNormalizerTests: XCTestCase {
    func testParsesOnlyOneSpacedDelimiterAndPreservesRawValue() {
        let parsed = MetadataNormalizer.parse(rawTitle: "  Artist Name — Song Name  ")
        XCTAssertEqual(parsed.rawTitle, "  Artist Name — Song Name  ")
        XCTAssertEqual(parsed.artist, "Artist Name")
        XCTAssertEqual(parsed.title, "Song Name")
        XCTAssertEqual(parsed.lookupKey, "artist name|song name")

        let ambiguous = MetadataNormalizer.parse(rawTitle: "Artist - Song - Version")
        XCTAssertNil(ambiguous.lookupKey)
        XCTAssertEqual(ambiguous.rawTitle, "Artist - Song - Version")
    }

    func testRejectsProgramAndAdvertisingLabelsFromLookup() {
        for raw in ["Morning News - Weather", "Station ID - Free Radio", "Advertisement - Buy Now"] {
            XCTAssertNil(MetadataNormalizer.parse(rawTitle: raw).lookupKey, raw)
        }
    }

    func testExplicitArtistAndTitleAreTrimmedAndNoiseIsRejected() {
        let parsed = MetadataNormalizer.parse(rawTitle: "Song", artist: " Artist ", title: " Title ")
        XCTAssertEqual(parsed.artist, "Artist")
        XCTAssertEqual(parsed.title, "Title")
        XCTAssertNil(MetadataNormalizer.parse(rawTitle: "News", artist: "Station", title: "News").lookupKey)
    }
}

final class MusicBrainzMatchTests: XCTestCase {
    func testMusicBrainzUserAgentRequiresAConfiguredMaintainerContact() {
        XCTAssertNil(MusicBrainzArtworkService.userAgent(for: nil))
        XCTAssertNil(MusicBrainzArtworkService.userAgent(for: "  \n"))
        XCTAssertNil(MusicBrainzArtworkService.userAgent(for: "maintainer\nInjected: value"))
        XCTAssertEqual(
            MusicBrainzArtworkService.userAgent(for: "support@example.com"),
            "FreeRadio/0.1 (iOS; contact: support@example.com)"
        )
    }

    func testRequiresHighScoreAndExactArtistAndTitle() {
        let exact = recording(score: 95, artist: "Example Artist", title: "Example Song")
        XCTAssertEqual(
            MusicBrainzArtworkService.confidentMatch([exact], artist: "Example Artist", title: "Example Song"),
            RecordingMatch(releaseGroupID: "group-id", releaseIDs: ["release-id"])
        )

        let wrongTitle = recording(score: 100, artist: "Example Artist", title: "Other Song")
        let lowScore = recording(score: 89, artist: "Example Artist", title: "Example Song")
        XCTAssertNil(MusicBrainzArtworkService.confidentMatch([wrongTitle, lowScore], artist: "Example Artist", title: "Example Song"))
    }

    private func recording(score: Int, artist: String, title: String) -> [String: Any] {
        [
            "score": score,
            "title": title,
            "artist-credit": [["name": artist]],
            "releases": [["id": "release-id", "release-group": ["id": "group-id"]]]
        ]
    }
}

@MainActor
final class ArtworkResolverTests: XCTestCase {
    func testDelayedOldTrackCannotReplaceNewTrackArtwork() async {
        let service = FakeArtworkService()
        service.responses["First Artist|First Song"] = Data([1])
        service.responses["Second Artist|Second Song"] = Data([2])
        service.delays["First Artist|First Song"] = .milliseconds(100)

        let resolver = ArtworkResolver(service: service)
        let station = Station(id: "station-a", name: "Station A", streamURL: URL(string: "https://example.com/a")!)
        resolver.resolve(station: station, metadata: MetadataNormalizer.parse(rawTitle: "First Artist - First Song"))
        resolver.resolve(station: station, metadata: MetadataNormalizer.parse(rawTitle: "Second Artist - Second Song"))
        try? await Task.sleep(for: .milliseconds(180))

        XCTAssertEqual(resolver.artworkData, Data([2]))
        XCTAssertFalse(resolver.isLoading)
    }

    func testFallsBackToStationArtworkAndClearsOnStationChange() async {
        let service = FakeArtworkService()
        service.stationResponses["https://example.com/art.png"] = Data([9])
        let resolver = ArtworkResolver(service: service)
        let stationA = Station(id: "station-a", name: "Station A", streamURL: URL(string: "https://example.com/a")!, artworkURL: URL(string: "https://example.com/art.png"))
        let stationB = Station(id: "station-b", name: "Station B", streamURL: URL(string: "https://example.com/b")!)

        resolver.resolve(station: stationA, metadata: nil)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(resolver.artworkData, Data([9]))

        resolver.resolve(station: stationB, metadata: nil)
        XCTAssertNil(resolver.artworkData)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(resolver.artworkData)
    }
}

private final class FakeArtworkService: ArtworkLookupService, @unchecked Sendable {
    var responses: [String: Data] = [:]
    var stationResponses: [String: Data] = [:]
    var delays: [String: Duration] = [:]

    func artworkData(for metadata: TrackMetadata) async throws -> Data? {
        let key = "\(metadata.artist ?? "")|\(metadata.title ?? "")"
        if let delay = delays[key] {
            // Deliberately ignore cancellation to verify the resolver's revision guard.
            try? await Task.sleep(for: delay)
        }
        return responses[key]
    }

    func stationArtworkData(from url: URL) async throws -> Data? {
        stationResponses[url.absoluteString]
    }
}
