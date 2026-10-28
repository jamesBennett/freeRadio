import Foundation

protocol ArtworkLookupService: Sendable {
    func artworkData(for metadata: TrackMetadata) async throws -> Data?
    func stationArtworkData(from url: URL) async throws -> Data?
}

/// MusicBrainz recording search followed by Cover Art Archive lookup. The service
/// returns image bytes only after a high-confidence text match.
final class MusicBrainzArtworkService: ArtworkLookupService, @unchecked Sendable {
    static let shared = MusicBrainzArtworkService()

    private let session: URLSession
    private let limiter: MusicBrainzRequestLimiter
    private let userAgent: String?
    private let maxJSONBytes = 1_000_000
    private let maxImageBytes = 5_000_000

    init(session: URLSession? = nil, limiter: MusicBrainzRequestLimiter = .shared, maintainerContact: String? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 12
            configuration.httpMaximumConnectionsPerHost = 2
            self.session = URLSession(configuration: configuration)
        }
        self.limiter = limiter
        let configuredContact = maintainerContact
            ?? Bundle.main.object(forInfoDictionaryKey: "FreeRadioMusicBrainzContact") as? String
        self.userAgent = Self.userAgent(for: configuredContact)
    }

    func artworkData(for metadata: TrackMetadata) async throws -> Data? {
        guard userAgent != nil, let artist = metadata.artist, let title = metadata.title else { return nil }
        let recordings = try await searchRecordings(artist: artist, title: title)
        guard let match = Self.confidentMatch(recordings, artist: artist, title: title) else { return nil }

        if let groupID = match.releaseGroupID,
           let data = try await fetchImage(URL(string: "https://coverartarchive.org/release-group/\(groupID)/front-500")!) {
            return data
        }
        for releaseID in match.releaseIDs.prefix(3) {
            try Task.checkCancellation()
            if let data = try await fetchImage(URL(string: "https://coverartarchive.org/release/\(releaseID)/front-500")!) {
                return data
            }
        }
        return nil
    }

    func stationArtworkData(from url: URL) async throws -> Data? {
        try await fetchImage(url)
    }

    static func userAgent(for maintainerContact: String?) -> String? {
        guard let contact = maintainerContact?.trimmingCharacters(in: .whitespacesAndNewlines),
              !contact.isEmpty, contact.count <= 200,
              contact.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        return "FreeRadio/0.1 (iOS; contact: \(contact))"
    }

    private func searchRecordings(artist: String, title: String) async throws -> [[String: Any]] {
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/recording/")!
        let q = "artist:\"\(artist)\" AND recording:\"\(title)\""
        components.queryItems = [
            URLQueryItem(name: "query", value: q),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = components.url else { return [] }
        try await limiter.waitForTurn()
        let data = try await fetch(url, accept: "application/json", limit: maxJSONBytes)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return root?["recordings"] as? [[String: Any]] ?? []
    }

    private func fetchImage(_ url: URL) async throws -> Data? {
        do {
            return try await fetch(url, accept: "image/*", limit: maxImageBytes)
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch let error as HTTPStatusError where error.statusCode == 404 || error.statusCode == 503 {
            return nil
        } catch {
            return nil
        }
    }

    private func fetch(_ url: URL, accept: String, limit: Int) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { throw HTTPStatusError(statusCode: http.statusCode) }
        if let length = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init), length > limit {
            throw URLError(.dataLengthExceedsMaximum)
        }
        if accept == "image/*", let mime = http.mimeType, !mime.hasPrefix("image/") {
            throw URLError(.cannotDecodeContentData)
        }
        var data = Data()
        data.reserveCapacity(min(limit, http.expectedContentLength > 0 ? Int(http.expectedContentLength) : 64_000))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }

    static func confidentMatch(_ results: [[String: Any]], artist: String, title: String) -> RecordingMatch? {
        let wantedArtist = normalized(artist)
        let wantedTitle = normalized(title)
        guard !wantedArtist.isEmpty, !wantedTitle.isEmpty else { return nil }
        for recording in results {
            guard let score = recording["score"] as? Int, score >= 90,
                  let candidateTitle = recording["title"] as? String,
                  normalized(candidateTitle) == wantedTitle,
                  let credits = recording["artist-credit"] as? [[String: Any]],
                  credits.contains(where: { credit in
                      let creditName = credit["name"] as? String
                          ?? (credit["artist"] as? [String: Any])?["name"] as? String
                      return creditName.map { normalized($0) == wantedArtist } ?? false
                  }) else { continue }

            let releases = recording["releases"] as? [[String: Any]] ?? []
            let groupID = releases.compactMap { ($0["release-group"] as? [String: Any])?["id"] as? String }.first
            let releaseIDs = releases.compactMap { $0["id"] as? String }
            return RecordingMatch(releaseGroupID: groupID, releaseIDs: releaseIDs)
        }
        return nil
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}

struct RecordingMatch: Equatable {
    let releaseGroupID: String?
    let releaseIDs: [String]
}

actor MusicBrainzRequestLimiter {
    static let shared = MusicBrainzRequestLimiter()
    private var nextRequestAt = ContinuousClock.now

    func waitForTurn() async throws {
        let now = ContinuousClock.now
        let slot = max(now, nextRequestAt)
        nextRequestAt = slot + .seconds(1)
        if slot > now {
            try await Task.sleep(for: now.duration(to: slot))
        }
    }
}

private struct HTTPStatusError: Error {
    let statusCode: Int
}
