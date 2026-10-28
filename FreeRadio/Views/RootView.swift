import SwiftUI

enum RadioTab: Hashable { case stations, player }

struct RootView: View {
    @Environment(StationLibrary.self) private var library
    @Environment(PlaybackSession.self) private var playback
    @Environment(ArtworkResolver.self) private var artwork
    @State private var tab = RadioTab.stations
    @State private var restored = false

    var body: some View {
        TabView(selection: $tab) {
            StationsView { station in
                library.select(station)
                playback.select(station)
                tab = .player
            } openPlayer: {
                tab = .player
            }
            .tabItem { Label("Stations", systemImage: "antenna.radiowaves.left.and.right") }
            .tag(RadioTab.stations)

            PlayerView { tab = .stations }
                .tabItem { Label("Player", systemImage: "play.circle.fill") }
                .tag(RadioTab.player)
        }
        .task {
            guard !restored else { return }
            restored = true
            playback.restoreSelection(library.lastSelected)
            refreshArtwork()
        }
        .onChange(of: playback.station) { _, _ in refreshArtwork() }
        .onChange(of: playback.metadata) { _, _ in refreshArtwork() }
        .onChange(of: artwork.artworkData) { _, data in playback.setArtwork(data) }
        .alert("Couldn’t save your stations", isPresented: Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.clearError() } }
        )) {
            Button("OK") { library.clearError() }
        } message: {
            Text(library.errorMessage ?? "Please try again.")
        }
    }

    private func refreshArtwork() {
        playback.setArtwork(nil)
        artwork.resolve(station: playback.station, metadata: playback.metadata)
    }
}
