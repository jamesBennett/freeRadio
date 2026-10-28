import Foundation
import Observation

@MainActor
@Observable
final class DirectoryStore {
    var query = ""
    var genre = ""
    private(set) var results: [Station] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hasMore = false

    private let client: any StationSearchClient
    private let pageSize: Int
    private var searchTask: Task<Void, Never>?
    private var revision = 0
    private var submittedQuery = ""
    private var submittedGenre = ""
    private var nextOffset = 0

    init() {
        client = StationDirectory()
        pageSize = 50
    }

    init(client: any StationSearchClient, pageSize: Int = 50) {
        self.client = client
        self.pageSize = max(1, pageSize)
    }

    /// Starts a search only when explicitly called by the UI.
    func search() {
        revision += 1
        let requestRevision = revision
        searchTask?.cancel()
        searchTask = nil

        let submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedGenre = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        self.submittedQuery = submittedQuery
        self.submittedGenre = submittedGenre
        nextOffset = 0
        guard !submittedQuery.isEmpty else {
            results = []
            hasMore = false
            isLoading = false
            errorMessage = nil
            return
        }

        results = []
        hasMore = false
        errorMessage = nil
        isLoading = true
        searchTask = Task { [weak self, client, pageSize] in
            do {
                let page = try await client.search(name: submittedQuery, genre: submittedGenre, offset: 0, limit: pageSize)
                guard let self, self.revision == requestRevision, !Task.isCancelled else { return }
                self.results = Self.uniqueStations(page.stations)
                self.hasMore = page.hasMore
                self.nextOffset = page.returnedCount
                self.isLoading = false
                self.searchTask = nil
            } catch is CancellationError {
                guard let self, self.revision == requestRevision else { return }
                self.isLoading = false
                self.searchTask = nil
            } catch {
                guard let self, self.revision == requestRevision, !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                self.hasMore = false
                self.searchTask = nil
            }
        }
    }

    func loadMore() {
        guard !isLoading, hasMore, !submittedQuery.isEmpty else { return }
        let submittedQuery = self.submittedQuery
        let submittedGenre = self.submittedGenre
        let requestRevision = revision
        let offset = nextOffset
        isLoading = true
        errorMessage = nil
        searchTask = Task { [weak self, client, pageSize] in
            do {
                let page = try await client.search(name: submittedQuery, genre: submittedGenre, offset: offset, limit: pageSize)
                guard let self, self.revision == requestRevision, !Task.isCancelled else { return }
                let existing = Set(self.results.map(\.id))
                self.results.append(contentsOf: Self.uniqueStations(page.stations).filter { !existing.contains($0.id) })
                self.hasMore = page.hasMore
                self.nextOffset += page.returnedCount
                self.isLoading = false
                self.searchTask = nil
            } catch is CancellationError {
                guard let self, self.revision == requestRevision else { return }
                self.isLoading = false
                self.searchTask = nil
            } catch {
                guard let self, self.revision == requestRevision, !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                self.searchTask = nil
            }
        }
    }

    func cancel() {
        revision += 1
        searchTask?.cancel()
        searchTask = nil
        isLoading = false
    }

    private static func uniqueStations(_ stations: [Station]) -> [Station] {
        var seen = Set<String>()
        return stations.filter { seen.insert($0.id).inserted }
    }
}
