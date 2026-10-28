import Foundation
import Observation

@MainActor
@Observable
final class ArtworkResolver {
    private(set) var artworkData: Data?
    private(set) var isLoading = false

    private let service: any ArtworkLookupService
    private var task: Task<Void, Never>?
    private var revision = 0
    private var currentKey: String?
    private var cache: [String: CacheEntry] = [:]
    private var cacheOrder: [String] = []
    private var cachedBytes = 0
    private let cacheEntryLimit = 40
    private let cacheByteLimit = 20_000_000

    init() {
        service = MusicBrainzArtworkService.shared
    }

    init(service: any ArtworkLookupService) {
        self.service = service
    }

    func resolve(station: Station?, metadata: TrackMetadata?) {
        let stationID = station?.id ?? "none"
        let stationArtworkURL = station?.artworkURL?.absoluteString ?? "no-station-art"
        let trackKey = metadata?.lookupKey ?? metadata?.rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "none"
        let key = "\(stationID)|\(stationArtworkURL)|\(trackKey)"
        guard key != currentKey else { return }

        currentKey = key
        revision += 1
        let requestRevision = revision
        task?.cancel()
        artworkData = nil
        guard let station else {
            isLoading = false
            task = nil
            return
        }

        isLoading = true
        task = Task { [weak self] in
            guard let self else { return }
            let musicKey = metadata?.lookupKey.map { "music|\($0)" }
            var enriched: Data?
            if let musicKey, let cached = self.cached(musicKey) {
                enriched = cached
            } else if let metadata, metadata.lookupKey != nil {
                do {
                    enriched = try await self.service.artworkData(for: metadata)
                } catch is CancellationError {
                    return
                } catch {
                    enriched = nil
                }
                guard self.revision == requestRevision, !Task.isCancelled else { return }
                if let musicKey { self.insertCache(enriched, for: musicKey) }
            }

            var result = enriched
            if result == nil, let artworkURL = station.artworkURL {
                let stationKey = "station|\(artworkURL.absoluteString)"
                if let cached = self.cached(stationKey) {
                    result = cached
                } else {
                    do {
                        result = try await self.service.stationArtworkData(from: artworkURL)
                    } catch is CancellationError {
                        return
                    } catch {
                        result = nil
                    }
                    guard self.revision == requestRevision, !Task.isCancelled else { return }
                    self.insertCache(result, for: stationKey)
                }
            }
            guard self.revision == requestRevision, !Task.isCancelled else { return }
            self.artworkData = result
            self.isLoading = false
            self.task = nil
        }
    }

    func cancel() {
        revision += 1
        task?.cancel()
        task = nil
        currentKey = nil
        artworkData = nil
        isLoading = false
    }

    private func cached(_ key: String) -> Data?? {
        guard let entry = cache[key] else { return nil }
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        return .some(entry.data)
    }

    private func insertCache(_ data: Data?, for key: String) {
        if let previous = cache.removeValue(forKey: key) {
            cachedBytes -= previous.data?.count ?? 0
            cacheOrder.removeAll { $0 == key }
        }
        cache[key] = CacheEntry(data: data)
        cachedBytes += data?.count ?? 0
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        while cacheOrder.count > cacheEntryLimit || cachedBytes > cacheByteLimit {
            let oldest = cacheOrder.removeFirst()
            if let evicted = cache.removeValue(forKey: oldest) {
                cachedBytes -= evicted.data?.count ?? 0
            }
        }
    }

    private struct CacheEntry {
        let data: Data?
    }
}
