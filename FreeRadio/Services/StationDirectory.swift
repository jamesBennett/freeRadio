import Foundation

struct StationSearchPage: Sendable {
    let stations: [Station]
    let hasMore: Bool
    let returnedCount: Int

    init(stations: [Station], hasMore: Bool, returnedCount: Int? = nil) {
        self.stations = stations
        self.hasMore = hasMore
        self.returnedCount = returnedCount ?? stations.count
    }
}

protocol StationSearchClient: Sendable {
    func search(name: String, genre: String, offset: Int, limit: Int) async throws -> StationSearchPage
}

enum StationDirectoryError: LocalizedError {
    case unavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The station directory is unavailable. Check your connection and try again."
        case .invalidResponse:
            return "The station directory returned data that could not be read."
        }
    }
}

/// Radio Browser client. It discovers API mirrors and moves to the next mirror
/// after a network or server error; station values remain provider-neutral.
actor StationDirectory: StationSearchClient {
    private let session: URLSession
    private var mirrors: [String] = []

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(name: String, genre: String, offset: Int, limit: Int) async throws -> StationSearchPage {
        let hosts = await availableMirrors()
        var lastError: Error = StationDirectoryError.unavailable

        for host in hosts {
            try Task.checkCancellation()
            do {
                let (stations, returnedCount) = try await search(host: host, name: name, genre: genre, offset: offset, limit: limit)
                mirrors = [host] + hosts.filter { $0 != host }
                return StationSearchPage(stations: stations, hasMore: returnedCount == limit, returnedCount: returnedCount)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Reports a user initiated station selection to Radio Browser's click counter.
    /// Failure is intentionally non-fatal because playback does not depend on it.
    func reportClick(stationID: String) async {
        guard UUID(uuidString: stationID) != nil else { return }
        let hosts = await availableMirrors()
        for host in hosts {
            for scheme in ["https", "http"] {
                guard !Task.isCancelled,
                      let url = URL(string: "\(scheme)://\(host)/json/url/\(stationID)") else { return }
                var request = URLRequest(url: url)
                request.setValue("FreeRadio/0.1", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 10
                do {
                    let (_, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                    mirrors = [host] + hosts.filter { $0 != host }
                    return
                } catch is CancellationError {
                    return
                } catch {
                    continue
                }
            }
        }
    }

    private func availableMirrors() async -> [String] {
        if !mirrors.isEmpty { return mirrors }

        let discovery = URL(string: "https://all.api.radio-browser.info/json/servers")!
        do {
            var request = URLRequest(url: discovery)
            request.setValue("FreeRadio/0.1", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 12
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw StationDirectoryError.unavailable }
            let records = try JSONDecoder().decode([MirrorRecord].self, from: data)
            var seen = Set<String>()
            mirrors = records.map(\.name).filter { !$0.isEmpty && seen.insert($0).inserted }
        } catch {
            // Discovery can be unavailable while known mirrors still work.
            mirrors = []
        }

        // API host fallbacks, not station data. Discovery can be down or can
        // advertise only mirrors that are failing, so known hosts follow it.
        let fallbacks = ["all.api.radio-browser.info", "de2.api.radio-browser.info", "de1.api.radio-browser.info", "fi1.api.radio-browser.info"]
        mirrors += fallbacks.filter { !mirrors.contains($0) }
        return mirrors
    }

    private func search(host: String, name: String, genre: String, offset: Int, limit: Int) async throws -> ([Station], Int) {
        var components = URLComponents()
        components.path = "/json/stations/search"
        var queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if !genre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "tag", value: genre))
        }
        components.queryItems = queryItems

        var lastError: Error = StationDirectoryError.unavailable
        for scheme in ["https", "http"] {
            try Task.checkCancellation()
            guard var urlParts = URLComponents(string: "\(scheme)://\(host)") else { continue }
            urlParts.path = components.path
            urlParts.queryItems = components.queryItems
            guard let url = urlParts.url else { continue }
            var request = URLRequest(url: url)
            request.setValue("FreeRadio/0.1", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    lastError = StationDirectoryError.unavailable
                    continue
                }
                let records: [StationRecord]
                do {
                    records = try JSONDecoder().decode([StationRecord].self, from: data)
                } catch {
                    throw StationDirectoryError.invalidResponse
                }
                return (records.compactMap(\.station), records.count)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

private struct MirrorRecord: Decodable {
    let name: String
}

private struct StationRecord: Decodable {
    let stationUUID: String?
    let name: String?
    let resolvedURL: String?
    let url: String?
    let homepage: String?
    let favicon: String?
    let country: String?
    let tags: String?

    enum CodingKeys: String, CodingKey {
        case stationUUID = "stationuuid"
        case name
        case resolvedURL = "url_resolved"
        case url
        case homepage
        case favicon
        case country
        case tags
    }

    var station: Station? {
        guard let id = stationUUID, !id.isEmpty,
              let name, !name.isEmpty,
              let stream = URL(string: resolvedURL ?? url ?? ""),
              let scheme = stream.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        return Station(
            id: id,
            name: name,
            streamURL: stream,
            homepageURL: validWebURL(homepage),
            artworkURL: validWebURL(favicon),
            country: country ?? "",
            tags: (tags ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        )
    }

    private func validWebURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        return url
    }
}
