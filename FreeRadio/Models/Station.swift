import Foundation

struct Station: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var name: String
    var streamURL: URL
    var homepageURL: URL?
    var artworkURL: URL?
    var country: String
    var tags: [String]

    init(id: String, name: String, streamURL: URL, homepageURL: URL? = nil,
         artworkURL: URL? = nil, country: String = "", tags: [String] = []) {
        self.id = id
        self.name = name
        self.streamURL = streamURL
        self.homepageURL = homepageURL
        self.artworkURL = artworkURL
        self.country = country
        self.tags = tags
    }
}

struct TrackMetadata: Equatable, Sendable {
    var rawTitle: String
    var artist: String?
    var title: String?

    var lookupKey: String? {
        guard let artist, !artist.isEmpty, let title, !title.isEmpty else { return nil }
        return "\(artist.lowercased())|\(title.lowercased())"
    }
}
