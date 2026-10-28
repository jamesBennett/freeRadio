import AVFoundation
import MediaPlayer
import Observation
import UIKit
import Foundation

enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case reconnecting
    case failed

    var isActive: Bool {
        switch self {
        case .loading, .playing, .reconnecting: true
        case .idle, .paused, .stopped, .failed: false
        }
    }
}

/// Owns the single live stream and the corresponding system playback controls.
@MainActor
@Observable
final class PlaybackSession: NSObject {
    private(set) var station: Station?
    private(set) var state: PlaybackState = .idle
    private(set) var metadata: TrackMetadata?
    private(set) var errorMessage: String?

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var currentItem: AVPlayerItem?
    @ObservationIgnored private var metadataOutput: AVPlayerItemMetadataOutput?
    @ObservationIgnored private let icyPoller = ICYTitlePoller()
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var itemNotificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var loadingWatchdogTask: Task<Void, Never>?
    @ObservationIgnored private var retryBudgetStartedAt: TimeInterval?
    @ObservationIgnored private var interruptionWasPlaying = false
    @ObservationIgnored private var interruptionUserOverride = false
    @ObservationIgnored private var artwork: Data?
    @ObservationIgnored private var explicitStop = false

    override init() {
        super.init()
        configureAudioSession()
        observeAudioSession()
        configureRemoteCommands()
        observePlayer()
    }

    func restoreSelection(_ station: Station?) {
        self.station = station
        state = station == nil ? .idle : .stopped
        metadata = nil
        errorMessage = nil
        explicitStop = false
        clearNowPlaying()
    }

    func select(_ station: Station) {
        generation += 1
        cancelRetry()
        startPlaybackBudget()
        player.pause()
        self.station = station
        metadata = nil
        artwork = nil
        errorMessage = nil
        explicitStop = false
        state = .loading
        try? AVAudioSession.sharedInstance().setActive(true)
        startFreshItem(for: station, generation: generation)
    }

    func play() {
        guard let station else { return }
        if state == .playing || state == .loading || state == .reconnecting { return }
        explicitStop = false
        interruptionUserOverride = true
        errorMessage = nil
        beginPlayback(for: station)
    }

    func pause() {
        guard station != nil else { return }
        generation += 1
        cancelRetry()
        cancelPlaybackBudget()
        icyPoller.stop()
        player.pause()
        state = .paused
        interruptionUserOverride = true
        updateNowPlaying(isStopped: false)
    }

    func stop() {
        generation += 1
        cancelRetry()
        cancelPlaybackBudget()
        explicitStop = true
        icyPoller.stop()
        player.pause()
        player.replaceCurrentItem(with: nil)
        clearItemNotifications()
        currentItem = nil
        metadataOutput = nil
        itemStatusObservation = nil
        metadata = nil
        artwork = nil
        errorMessage = nil
        state = station == nil ? .idle : .stopped
        clearNowPlaying()
        deactivateAudioSession()
    }

    func retry() {
        guard let station else { return }
        errorMessage = nil
        explicitStop = false
        beginPlayback(for: station)
    }

    func setArtwork(_ data: Data?) {
        artwork = data
        guard station != nil, state != .stopped, state != .idle else { return }
        updateNowPlaying(isStopped: false)
    }

    private func beginPlayback(for station: Station) {
        generation += 1
        cancelRetry()
        startPlaybackBudget()
        state = .loading
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Some routes reject activation transiently. The player can still report the
            // actual playback result; do not fail the stream solely on session setup.
        }
        startFreshItem(for: station, generation: generation)
    }

    private func startFreshItem(for station: Station, generation itemGeneration: Int) {
        clearItemNotifications()
        let item = AVPlayerItem(url: station.streamURL)
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(self, queue: .main)
        item.add(output)
        currentItem = item
        metadataOutput = output
        icyPoller.start(url: station.streamURL) { [weak self] title in
            guard let self, self.generation == itemGeneration, self.currentItem === item,
                  self.state.isActive else { return }
            self.applyStreamMetadata(title: title, artist: nil)
        }
        let center = NotificationCenter.default
        itemNotificationTokens.append(center.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.currentItem === item else { return }
                self.handleTransientFailure(generation: itemGeneration, message: nil)
            }
        })
        itemNotificationTokens.append(center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] note in
            let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.currentItem === item else { return }
                self.handleTransientFailure(generation: itemGeneration, message: message)
            }
        })
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == itemGeneration, self.currentItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    self.cancelRetry()
                    self.cancelPlaybackBudget()
                    self.state = .playing
                    self.errorMessage = nil
                    self.updateNowPlaying(isStopped: false)
                case .failed:
                    self.handleTransientFailure(generation: itemGeneration, message: item.error?.localizedDescription)
                case .unknown: break
                @unknown default: break
                }
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
        updateNowPlaying(isStopped: false)
    }

    private func observePlayer() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self, let currentItem = self.currentItem,
                      player.currentItem === currentItem,
                      self.state != .paused, self.state != .stopped, !self.explicitStop else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.state = .playing
                    self.updateNowPlaying(isStopped: false)
                case .waitingToPlayAtSpecifiedRate:
                    if self.state != .reconnecting { self.state = .loading }
                case .paused: break
                @unknown default: break
                }
            }
        }
    }

    private func handleTransientFailure(generation expected: Int, message: String?) {
        guard PlaybackEventPolicy.accepts(generation: expected, currentGeneration: generation,
                                          explicitlyStopped: explicitStop, state: state), station != nil else { return }
        guard retryTask == nil else { return }
        state = .reconnecting
        errorMessage = nil
        let retryGeneration = generation
        retryTask = Task { @MainActor [weak self] in
            let policy = PlaybackRetryPolicy(startedAt: self?.retryBudgetStartedAt ?? ProcessInfo.processInfo.systemUptime)
            var delay = policy.initialDelay
            while !Task.isCancelled, policy.shouldRetry(at: ProcessInfo.processInfo.systemUptime) {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self, self.generation == retryGeneration,
                      self.state == .reconnecting, !self.explicitStop else { return }
                guard let station = self.station else { return }
                self.startFreshItem(for: station, generation: retryGeneration)
                delay = policy.nextDelay(after: delay)
            }
            guard let self, self.generation == retryGeneration, self.state == .reconnecting else { return }
            self.retryTask = nil
            self.state = .failed
            self.errorMessage = message ?? "The stream could not be reached. Try again."
            self.player.pause()
            self.updateNowPlaying(isStopped: false)
        }
    }

    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
    }

    private func startPlaybackBudget() {
        cancelPlaybackBudget()
        let startedAt = ProcessInfo.processInfo.systemUptime
        retryBudgetStartedAt = startedAt
        let expectedGeneration = generation
        loadingWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, self.generation == expectedGeneration,
                  (self.state == .loading || self.state == .reconnecting) else { return }
            self.handleTransientFailure(generation: expectedGeneration, message: nil)
        }
    }

    private func cancelPlaybackBudget() {
        loadingWatchdogTask?.cancel()
        loadingWatchdogTask = nil
        retryBudgetStartedAt = nil
    }

    private func clearItemNotifications() {
        let center = NotificationCenter.default
        itemNotificationTokens.forEach(center.removeObserver)
        itemNotificationTokens.removeAll()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
        } catch {
            errorMessage = "Audio playback setup failed."
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor [weak self] in self?.handleInterruption(note) }
        })
        notificationTokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor [weak self] in self?.handleRouteChange(note) }
        })
    }

    private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            interruptionWasPlaying = state == .playing || state == .loading || state == .reconnecting
            interruptionUserOverride = false
            if interruptionWasPlaying {
                player.pause()
                state = .paused
                updateNowPlaying(isStopped: false)
            }
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if interruptionWasPlaying, !interruptionUserOverride, !explicitStop, options.contains(.shouldResume) {
                play()
            }
            interruptionWasPlaying = false
        @unknown default: break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable,
              state == .playing || state == .loading || state == .reconnecting else { return }
        pause()
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.stopCommand.isEnabled = true
        remoteCommandTargets.append((commands.playCommand, commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.play() }
            return .success
        }))
        remoteCommandTargets.append((commands.pauseCommand, commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
            return .success
        }))
        remoteCommandTargets.append((commands.stopCommand, commands.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop() }
            return .success
        }))
    }

    private func updateNowPlaying(isStopped: Bool) {
        guard let station else { clearNowPlaying(); return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: metadata?.title ?? station.name,
            MPMediaItemPropertyArtist: metadata?.artist ?? "Live Radio",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0
        ]
        if let artwork, let image = UIImage(data: artwork) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isStopped ? .stopped : (state == .playing ? .playing : .paused)
    }

    private func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}

extension PlaybackSession: AVPlayerItemMetadataOutputPushDelegate {
    nonisolated func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                                    didOutputTimedMetadataGroups metadataGroups: [AVTimedMetadataGroup],
                                    from track: AVPlayerItemTrack?) {
        let values = metadataGroups.flatMap(\.items).reduce(into: (title: Optional<String>.none, artist: Optional<String>.none)) { result, item in
            let key = item.commonKey?.rawValue.lowercased() ?? item.identifier?.rawValue.lowercased() ?? ""
            let value = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value, !value.isEmpty else { return }
            if key.contains("artist") { result.artist = value }
            else if key.contains("title") || key.contains("name") { result.title = value }
        }
        guard values.title != nil || values.artist != nil else { return }
        Task { @MainActor [weak self] in
            guard let self, output === self.metadataOutput else { return }
            self.applyStreamMetadata(title: values.title, artist: values.artist)
        }
    }

    /// Shared by native timed metadata and the ICY poller; an unchanged value is ignored.
    @MainActor
    fileprivate func applyStreamMetadata(title: String?, artist: String?) {
        let parsed: TrackMetadata
        if let artist, let title {
            parsed = MetadataNormalizer.parse(rawTitle: "\(artist) - \(title)", artist: artist, title: title)
        } else {
            parsed = MetadataNormalizer.parse(rawTitle: title ?? artist ?? "")
        }
        guard parsed != metadata else { return }
        let previousKey = metadata?.lookupKey
        metadata = parsed
        if parsed.lookupKey != previousKey { artwork = nil }
        updateNowPlaying(isStopped: false)
    }
}

struct PlaybackRetryPolicy: Equatable {
    let startedAt: TimeInterval
    let budget: TimeInterval = 30
    let initialDelay: TimeInterval = 1
    let maximumDelay: TimeInterval = 8

    func shouldRetry(at now: TimeInterval) -> Bool { now - startedAt < budget }
    func nextDelay(after delay: TimeInterval) -> TimeInterval { min(delay * 2, maximumDelay) }
}

enum PlaybackEventPolicy {
    static func accepts(generation: Int, currentGeneration: Int, explicitlyStopped: Bool,
                        state: PlaybackState) -> Bool {
        generation == currentGeneration && !explicitlyStopped && state != .paused && state != .stopped
    }
}
