import SwiftUI
import MediaPlayer

struct PlayerView: View {
    @Environment(PlaybackSession.self) private var playback
    @Environment(ArtworkResolver.self) private var artwork
    @Environment(StationLibrary.self) private var library
    @State private var volumeFrame: CGRect = .zero
    let findStation: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("FREE RADIO").font(.caption.weight(.bold))
                Rectangle().fill(GridTheme.ink.opacity(0.5)).frame(height: 0.5)
                if let station = playback.station {
                    HStack(alignment: .firstTextBaseline) {
                        Text("NOW PLAYING").font(.caption.weight(.bold))
                        Spacer()
                        Text(statusText.uppercased())
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundStyle(playback.state == .playing ? .white : GridTheme.navy)
                            .background(playback.state == .playing ? GridTheme.navy : GridTheme.surface,
                                        in: RoundedRectangle(cornerRadius: 5))
                        Button { library.togglePin(station) } label: {
                            Image(systemName: library.isPinned(station) ? "pin.fill" : "pin")
                                .font(.title3)
                                .foregroundStyle(library.isPinned(station) ? GridTheme.navy : GridTheme.muted)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("\(library.isPinned(station) ? "Unpin" : "Pin") \(station.name)")
                    }
                    Text(station.name.uppercased())
                        .font(GridTheme.display(34, relativeTo: .title)).tracking(-1)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    artworkView

                    VStack(alignment: .leading, spacing: 6) {
                        if let metadata = playback.metadata, !metadata.rawTitle.isEmpty {
                            Text((metadata.title ?? metadata.rawTitle).uppercased())
                                .font(GridTheme.display(43)).tracking(-1.5)
                                .fixedSize(horizontal: false, vertical: true)
                            if let artist = metadata.artist {
                                Text(artist).font(GridTheme.display(24, relativeTo: .title2))
                            }
                        } else {
                            Text("TUNED IN.")
                                .font(GridTheme.display(43)).tracking(-1.5)
                            Text(playback.state == .stopped || playback.state == .idle
                                 ? "Press Play to listen."
                                 : "Track information unavailable")
                                .foregroundStyle(GridTheme.muted)
                        }
                    }
                    .accessibilityElement(children: .combine)

                    if playback.state == .loading || playback.state == .reconnecting {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(playback.state == .reconnecting ? "Reconnecting…" : "Connecting…")
                                .font(.subheadline).foregroundStyle(GridTheme.muted)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if let message = playback.errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(message).font(.subheadline).foregroundStyle(GridTheme.muted)
                            Button("Retry") { playback.retry() }
                                .font(.body.weight(.semibold)).frame(minHeight: 44)
                        }
                    }

                    let action = TransportAction(state: playback.state)
                    HStack {
                        Spacer(minLength: 0)
                        transportButton(symbol: action == .stop ? "stop.fill" : "play.fill",
                                        title: action == .stop ? "Stop" : "Play") {
                            if action == .stop { playback.stop() } else { playback.play() }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("VOLUME").font(.caption.weight(.medium))
                        SystemVolumeView()
                            .frame(height: 44)
                            .background(GeometryReader { proxy in
                                Color.clear.onAppear { volumeFrame = proxy.frame(in: .named("player")) }
                                    .onChange(of: proxy.frame(in: .named("player"))) { _, frame in volumeFrame = frame }
                            })
                            .accessibilityLabel("Output volume")
                    }
                    .padding(.top, 8)
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("READY\nWHEN\nYOU ARE.")
                            .font(GridTheme.display(60)).tracking(-2)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 76, weight: .ultraLight))
                            .foregroundStyle(GridTheme.navy)
                            .padding(.vertical, 24)
                            .accessibilityHidden(true)
                        Text("Find a station to start listening.")
                            .font(.title3).foregroundStyle(GridTheme.muted)
                        Button(action: findStation) {
                            Label("Find a station", systemImage: "magnifyingglass")
                                .font(.headline).padding(.horizontal, 22).padding(.vertical, 16)
                                .foregroundStyle(.white)
                                .background(GridTheme.navy, in: Capsule())
                        }
                    }
                    .padding(.top, 24)
                }
            }
            .padding(20)
        }
        .coordinateSpace(name: "player")
        .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .named("player"))
                .onEnded { value in
                    // Volume slider drags are horizontal too; never treat them as navigation.
                    guard !volumeFrame.contains(value.startLocation),
                          PlayerSwipe.returnsToStations(translation: value.translation,
                                                        predictedEnd: value.predictedEndTranslation) else { return }
                    findStation()
                }
        )
        .background(GridTheme.paper)
        .foregroundStyle(GridTheme.ink)
    }

    private var artworkView: some View {
        GeometryReader { geometry in
            ZStack {
                GridTheme.surface
                if let data = artwork.artworkData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.width).clipped()
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 68, weight: .ultraLight))
                        Text("FREE RADIO").font(.caption.weight(.bold)).tracking(3)
                    }
                    .foregroundStyle(GridTheme.navy)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .aspectRatio(1, contentMode: .fit)
        // Capped so the transport controls stay above the tab bar on standard phones.
        .frame(maxWidth: 260)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var statusText: String {
        switch playback.state {
        case .playing: return "● Live"
        case .loading: return "Connecting"
        case .reconnecting: return "Reconnecting"
        case .paused: return "Paused"
        case .failed: return "Unavailable"
        case .idle, .stopped: return "Stopped"
        }
    }

    private func transportButton(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .frame(width: 84, height: 84)
                    .foregroundStyle(Color.white)
                    .background(GridTheme.ink, in: Circle())
                Text(title).font(.caption.weight(.medium)).foregroundStyle(GridTheme.ink)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Live radio has no meaningful pause, so the single transport control is Play or Stop.
enum TransportAction: Equatable {
    case play, stop

    init(state: PlaybackState) {
        self = state.isActive ? .stop : .play
    }
}

enum PlayerSwipe {
    /// A deliberate, mostly horizontal swipe in either direction returns to Stations:
    /// either a long drag or a short flick whose momentum would carry it far.
    static func returnsToStations(translation: CGSize, predictedEnd: CGSize? = nil) -> Bool {
        guard abs(translation.width) > abs(translation.height) * 2 else { return false }
        return abs(translation.width) >= 80 || abs((predictedEnd ?? translation).width) >= 150
    }
}

struct SystemVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.tintColor = UIColor(red: 0.09, green: 0.23, blue: 0.40, alpha: 1)
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
