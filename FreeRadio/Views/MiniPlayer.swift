import SwiftUI

struct MiniPlayer: View {
    @Environment(PlaybackSession.self) private var playback
    @Environment(ArtworkResolver.self) private var artwork
    let openPlayer: () -> Void

    var body: some View {
        if let station = playback.station {
            HStack(spacing: 12) {
                Button(action: openPlayer) {
                    HStack(spacing: 12) {
                        if let data = artwork.artworkData, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .accessibilityHidden(true)
                        } else {
                            StationArtwork(url: station.artworkURL, size: 48)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(playback.metadata?.title ?? playback.metadata?.rawTitle ?? station.name)
                                .font(.headline).foregroundStyle(GridTheme.ink).lineLimit(1)
                            Text(playback.metadata == nil ? statusText : playback.metadata?.artist ?? station.name)
                                .font(.subheadline).foregroundStyle(GridTheme.muted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityHint("Opens Player")
                let action = TransportAction(state: playback.state)
                Button {
                    if action == .stop { playback.stop() } else { playback.play() }
                } label: {
                    Image(systemName: action == .stop ? "stop.fill" : "play.fill")
                        .font(.title2).foregroundStyle(GridTheme.ink)
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel(action == .stop ? "Stop" : "Play")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(GridTheme.paper)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private var statusText: String {
        switch playback.state {
        case .playing: return "Live"
        case .loading: return "Connecting…"
        case .reconnecting: return "Reconnecting…"
        case .paused: return "Paused"
        case .failed: return "Unavailable"
        case .idle, .stopped: return "Stopped"
        }
    }
}
