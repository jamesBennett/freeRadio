import XCTest
@testable import FreeRadio

final class DirectoryTests: XCTestCase {
    @MainActor
    func testEmptyQueryDoesNotCallDirectory() async {
        let client = FakeDirectoryClient(pages: [])
        let store = DirectoryStore(client: client, pageSize: 2)
        store.search()
        await waitUntilIdle(store)

        XCTAssertTrue(store.results.isEmpty)
        XCTAssertFalse(store.isLoading)
        let requestCount = await client.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    @MainActor
    func testSearchAndPaginationDedupeByDirectoryIdentity() async {
        let first = Station(id: "uuid-a", name: "Station A", streamURL: URL(string: "https://example.com/a")!)
        let second = Station(id: "uuid-b", name: "Station B", streamURL: URL(string: "https://example.com/b")!)
        let sameIDChangedName = Station(id: "uuid-a", name: "Renamed A", streamURL: URL(string: "https://example.com/new-a")!)
        let client = FakeDirectoryClient(pages: [
            StationSearchPage(stations: [first], hasMore: true),
            StationSearchPage(stations: [sameIDChangedName, second], hasMore: false)
        ])
        let store = DirectoryStore(client: client, pageSize: 1)
        store.query = "Station"
        store.genre = "jazz"

        store.search()
        await waitUntilIdle(store)
        XCTAssertEqual(store.results.map(\.id), ["uuid-a"])
        store.loadMore()
        await waitUntilIdle(store)

        XCTAssertEqual(store.results.map(\.id), ["uuid-a", "uuid-b"])
        XCTAssertFalse(store.hasMore)
        let requests = await client.requests
        XCTAssertEqual(requests.map(\.name), ["Station", "Station"])
        XCTAssertEqual(requests.map(\.genre), ["jazz", "jazz"])
        XCTAssertEqual(requests.map(\.offset), [0, 1])
    }

    @MainActor
    func testCancelPreventsLateResultsFromReplacingCurrentState() async {
        let station = Station(id: "uuid-late", name: "Station A", streamURL: URL(string: "https://example.com/a")!)
        let client = FakeDirectoryClient(pages: [StationSearchPage(stations: [station], hasMore: false)], delayNanoseconds: 40_000_000)
        let store = DirectoryStore(client: client)
        store.query = "Station"
        store.search()
        store.cancel()
        await waitUntilIdle(store)

        XCTAssertTrue(store.results.isEmpty)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    private func waitUntilIdle(_ store: DirectoryStore) async {
        for _ in 0..<500 {
            if !store.isLoading { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

private actor FakeDirectoryClient: StationSearchClient {
    struct Request: Sendable {
        let name: String
        let genre: String
        let offset: Int
        let limit: Int
    }

    private var pages: [StationSearchPage]
    private(set) var requests: [Request] = []
    private let delayNanoseconds: UInt64

    init(pages: [StationSearchPage], delayNanoseconds: UInt64 = 0) {
        self.pages = pages
        self.delayNanoseconds = delayNanoseconds
    }

    var requestCount: Int { requests.count }

    func search(name: String, genre: String, offset: Int, limit: Int) async throws -> StationSearchPage {
        requests.append(Request(name: name, genre: genre, offset: offset, limit: limit))
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        guard !pages.isEmpty else { return StationSearchPage(stations: [], hasMore: false) }
        return pages.removeFirst()
    }
}
