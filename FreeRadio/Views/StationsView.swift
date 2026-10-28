import SwiftUI

struct StationsView: View {
    @Environment(StationLibrary.self) private var library
    @Environment(DirectoryStore.self) private var directory
    @Environment(PlaybackSession.self) private var playback
    let selectStation: (Station) -> Void
    let openPlayer: () -> Void
    @State private var submitted = false
    @FocusState private var searchFocused: Bool
    @State private var editMode = EditMode.inactive

    private let genres = ["", "jazz", "classical", "rock", "news", "electronic"]

    var body: some View {
        @Bindable var directory = directory

        NavigationStack {
            List {
                VStack(alignment: .leading, spacing: 16) {
                    Text("FREE RADIO").font(.caption.weight(.bold))
                    Rectangle().fill(GridTheme.ink.opacity(0.5)).frame(height: 0.5)
                    Text("STATIONS")
                        .font(GridTheme.display(49)).tracking(-2)
                        .minimumScaleFactor(0.65).lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(GridTheme.muted)
                        TextField("Search stations", text: $directory.query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .focused($searchFocused)
                            .onSubmit(runSearch)
                            .accessibilityIdentifier("stationSearch")
                        if !directory.query.isEmpty {
                            Button {
                                directory.query = ""
                                directory.cancel()
                                submitted = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .accessibilityLabel("Clear search")
                        }
                        Button(action: runSearch) {
                            Image(systemName: "arrow.right")
                                .font(.body.weight(.bold))
                                .frame(minWidth: 36, minHeight: 44)
                        }
                        .disabled(directory.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Search")
                    }
                    .padding(.leading, 12).padding(.trailing, 4)
                    .background(GridTheme.surface, in: RoundedRectangle(cornerRadius: 10))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(genres, id: \.self) { genre in
                                Button {
                                    directory.genre = genre
                                    if submitted { runSearch() }
                                } label: {
                                    Text(genre.isEmpty ? "All" : genre.capitalized)
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 20).frame(minHeight: 44)
                                        .foregroundStyle(directory.genre == genre ? Color.white : GridTheme.ink)
                                        .background(directory.genre == genre ? GridTheme.navy : GridTheme.surface, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(directory.genre == genre ? .isSelected : [])
                            }
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 22, trailing: 20))

                Section {
                    if library.pins.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "pin").font(.title2).foregroundStyle(GridTheme.navy)
                            Text("YOUR RADIO.\nYOUR STATIONS.")
                                .font(GridTheme.display(30, relativeTo: .title)).tracking(-0.9)
                            Text("Search for a station and tap its pin to keep it here.")
                                .font(.body).foregroundStyle(GridTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Find a station") { searchFocused = true }
                                .font(.body.weight(.semibold)).frame(minHeight: 44)
                        }
                        .padding(.vertical, 20)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(library.pins) { station in
                            stationRow(station)
                        }
                        .onMove { library.movePins(from: $0, to: $1) }
                    }
                } header: {
                    HStack {
                        SectionRule(title: "PINNED", count: library.pins.count)
                        if library.pins.count > 1 {
                            Button(editMode == .active ? "Done" : "Reorder") {
                                withAnimation { editMode = editMode == .active ? .inactive : .active }
                            }
                            .font(.caption.weight(.semibold))
                            .frame(minHeight: 44)
                        }
                    }
                    .textCase(nil)
                }

                if submitted {
                    Section {
                        if let message = directory.errorMessage {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Search unavailable", systemImage: "wifi.exclamationmark").font(.headline)
                                Text(message).font(.subheadline).foregroundStyle(GridTheme.muted)
                                Button("Try again", action: runSearch).frame(minHeight: 44)
                            }
                            .padding(.vertical, 12)
                        }
                        ForEach(directory.results) { station in stationRow(station) }
                        if directory.isLoading {
                            HStack { ProgressView(); Text("Finding stations…").foregroundStyle(GridTheme.muted) }
                                .padding(.vertical, 12)
                                .accessibilityElement(children: .combine)
                        } else if directory.results.isEmpty && directory.errorMessage == nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No stations found").font(.headline)
                                Text("Try another name or remove the genre filter.")
                                    .foregroundStyle(GridTheme.muted)
                            }
                            .padding(.vertical, 16)
                        } else if directory.hasMore {
                            Button("More stations") { directory.loadMore() }
                                .frame(minHeight: 44)
                        }
                    } header: {
                        SectionRule(title: "SEARCH RESULTS", count: directory.results.count)
                            .textCase(nil)
                    }
                }
            }
            .buttonStyle(.plain)
            .environment(\.editMode, $editMode)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(GridTheme.paper)
            .foregroundStyle(GridTheme.ink)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if playback.station != nil { MiniPlayer(openPlayer: openPlayer) }
            }
        }
    }

    private func stationRow(_ station: Station) -> some View {
        HStack(spacing: 12) {
            Button { selectStation(station) } label: {
                HStack(spacing: 12) {
                    StationArtwork(url: station.artworkURL)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(station.name).font(GridTheme.display(20, relativeTo: .headline))
                            .foregroundStyle(GridTheme.ink).multilineTextAlignment(.leading)
                        Text([station.tags.first?.capitalized, station.country.isEmpty ? nil : station.country]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(GridTheme.muted)
                            .lineLimit(2).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    if playback.station?.id == station.id && playback.state.isActive {
                        Image(systemName: "waveform").foregroundStyle(GridTheme.navy)
                            .accessibilityLabel("Playing")
                    }
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Play \(station.name)")
            Button { library.togglePin(station) } label: {
                Image(systemName: library.isPinned(station) ? "pin.fill" : "pin")
                    .font(.title3).foregroundStyle(library.isPinned(station) ? GridTheme.navy : GridTheme.muted)
                    .frame(width: 44, height: 56)
            }
            .accessibilityLabel("\(library.isPinned(station) ? "Unpin" : "Pin") \(station.name)")
        }
        .padding(.vertical, 6)
        .listRowBackground(GridTheme.paper)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 12))
    }

    private func runSearch() {
        guard !directory.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        submitted = true
        searchFocused = false
        editMode = .inactive
        directory.search()
    }
}
