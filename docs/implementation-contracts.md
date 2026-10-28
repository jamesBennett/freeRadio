# Implementation contracts

The root agent owns shared Models/Station.swift, app entry point, SwiftUI views, Xcode project and integration. Workers only edit their assigned directories and tests. All app code lives under FreeRadio/ and tests under FreeRadioTests/. Use SwiftUI/Observation, iOS 18+, Swift 5 language mode, no dependencies. No real stations, station-specific names/URLs, defaults, metadata adapters or fixtures in shipped code. Test values are generic Station A/B and example.com URLs.

## Shared types (root owned)

Station: Codable, Hashable, Identifiable, Sendable; id:String (directory UUID), name:String, streamURL:URL, homepageURL:URL?, artworkURL:URL?, country:String, tags:[String].
TrackMetadata: Equatable, Sendable; rawTitle:String, artist:String?, title:String?, lookupKey:String? (normalized artist/title).

## Directory and persistence worker

Own Services/StationDirectory.swift, Services/StationLibrary.swift, Services/DirectoryStore.swift, tests DirectoryTests.swift and LibraryTests.swift.
@MainActor @Observable final class StationLibrary: init(storageURL:URL? = nil); private(set) var pins:[Station], lastSelected:Station?, errorMessage:String?; func isPinned(_ station:Station)->Bool; func togglePin(_ station:Station); func movePins(from:IndexSet,to:Int); func select(_ station:Station); func clearError(). No defaults. Ordered atomic JSON persistence, preserve a good file on decode failure until explicit recovery; surface errors. Last selection independent from pin membership.
@MainActor @Observable final class DirectoryStore: init(); var query:String, genre:String (empty means All); private(set) var results:[Station], isLoading:Bool, errorMessage:String?, hasMore:Bool; func search(); func loadMore(); func cancel(). Submit search explicitly, no API call per keystroke. Cancel/revision-protect stale requests. Search name with optional genre tag. Pagination. Empty query should not load a station list. StationDirectory can be internal actor/service; discover Radio Browser mirrors, cache/failover, HTTPS where available, User-Agent FreeRadio/0.1. Distinguish empty results vs service failures. Avoid duplicate IDs. Include generic click-count reporting helper if suitable, never report from tests.

## Playback worker

Own Playback/ and PlaybackTests.swift. @MainActor @Observable final class PlaybackSession: init(); private(set) var station:Station?, state:PlaybackState, metadata:TrackMetadata?, errorMessage:String?; func select(_ station:Station); func restoreSelection(_ station:Station?); func play(); func pause(); func stop(); func retry(); func setArtwork(_ data:Data?). PlaybackState enum cases idle, loading, playing, paused, stopped, reconnecting, failed; computed isActive:Bool for loading/playing/reconnecting. Own AVPlayer, AVAudioSession, interruption/route notifications, MPNowPlayingInfoCenter and MPRemoteCommandCenter. Pause retains controls; Play after Pause goes live by replacing item; Stop clears system session and selection stays. Selection switches immediately. Report raw and normalized generic metadata; extraction normalization may be shared with Metadata worker below. Native AVPlayerItemMetadataOutput handles ICY and common title/artist. Per-item generation protection. Bounded 30sec reconnect, no resume after explicit Pause/Stop during interruption, route loss pauses. First restore no autoplay. setArtwork updates only current display (root calls generation-protected resolver). Native metadata failures never stop audio. Keep services testable via pure state policy helpers rather than trying to instantiate AVAudioSession in unit tests.

## Metadata worker

Own Metadata/ and MetadataTests.swift. Provide enum MetadataNormalizer { static func parse(rawTitle:String, artist:String? = nil, title:String? = nil)->TrackMetadata }. Conservatively split artist/title on spaced delimiter only, reject generic program/station/ad text for lookups while retaining raw display text, no broadcaster-specific rules. Playback worker depends on this exact API.
@MainActor @Observable final class ArtworkResolver: init(); private(set) var artworkData:Data?, isLoading:Bool; func resolve(station:Station?, metadata:TrackMetadata?); func cancel(). Clear previous result immediately on station/track key change, cancel/revision protect, prefer confident MusicBrainz matches -> release or release-group CAA artwork, fallback station.artworkURL then nil. Throttle MusicBrainz <=1 request/sec including concurrent changes; meaningful User-Agent; small bounded hit/miss cache; response/image size caps, networking timeouts. No recognition or Last.fm. Do not guess matches from just program names. Add useful parsing/matching/stale-response tests with injected services or pure components. Do not make live API requests from unit tests.

## Integration

Root coordinates selection: library.select, playback.select, open Player tab. Observe playback station/metadata and call resolver.resolve. Observe resolver artworkData and call playback.setArtwork. Last-selected restored once at launch. Shared loading/error states must be accessible; large text can scroll; persistent mini player on Stations. System MPVolumeView wrapper for volume. No autoplay or directory defaults.
