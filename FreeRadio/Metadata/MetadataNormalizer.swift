import Foundation

enum MetadataNormalizer {
    /// Retains the broadcaster's original text while exposing only plausible music
    /// fields for catalog lookup. Stream metadata is inconsistent, so parsing is
    /// intentionally limited to an explicit artist/title pair or a single spaced
    /// separator.
    static func parse(rawTitle: String, artist: String? = nil, title: String? = nil) -> TrackMetadata {
        let cleanRaw = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        var parsedArtist = cleaned(artist)
        var parsedTitle = cleaned(title)

        if let parsedArtist, parsedTitle == nil,
           let raw = cleaned(rawTitle), raw.caseInsensitiveCompare(parsedArtist) != .orderedSame {
            parsedTitle = raw
        }
        if parsedArtist == nil, parsedTitle == nil, !cleanRaw.isEmpty {
            let separators = [" — ", " – ", " - ", " | "]
            for separator in separators {
                let pieces = cleanRaw.components(separatedBy: separator)
                if pieces.count == 2,
                   let left = cleaned(pieces[0]), let right = cleaned(pieces[1]) {
                    parsedArtist = left
                    parsedTitle = right
                    break
                }
            }
        }

        if let a = parsedArtist, let t = parsedTitle,
           isLookupNoise(a) || isLookupNoise(t) {
            parsedArtist = nil
            parsedTitle = nil
        } else if parsedArtist == nil && parsedTitle != nil {
            // A title alone is too ambiguous to search reliably.
            parsedTitle = nil
        }

        return TrackMetadata(rawTitle: rawTitle, artist: parsedArtist, title: parsedTitle)
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func isLookupNoise(_ value: String) -> Bool {
        let normalized = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
        let exact = Set([
            "ad", "advert", "advertisement", "commercial", "station id", "station identification",
            "now playing", "coming up", "on air", "live", "news", "weather", "traffic",
            "talk", "talk show", "interview", "unknown", "untitled", "no artist", "no title"
        ])
        let blockedTerms = Set(["advert", "advertisement", "commercial", "station", "news", "weather", "traffic", "talk", "interview", "live", "coming up"])
        return exact.contains(normalized) || normalized.split(separator: " ").contains { blockedTerms.contains(String($0)) }
    }
}
