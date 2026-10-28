import SwiftUI

@main
struct FreeRadioApp: App {
    @State private var library = StationLibrary()
    @State private var directory = DirectoryStore()
    @State private var playback = PlaybackSession()
    @State private var artwork = ArtworkResolver()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(directory)
                .environment(playback)
                .environment(artwork)
                .tint(GridTheme.navy)
                .preferredColorScheme(.light)
        }
    }
}
