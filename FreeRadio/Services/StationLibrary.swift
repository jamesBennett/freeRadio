import Foundation
import Observation

@MainActor
@Observable
final class StationLibrary {
    private(set) var pins: [Station] = []
    private(set) var lastSelected: Station?
    private(set) var errorMessage: String?

    private let storage: any StationLibraryStorage
    private var canPersist = true

    init(storageURL: URL? = nil) {
        let url = storageURL ?? Self.defaultStorageURL()
        storage = FileStationLibraryStorage(url: url)
        loadFromStorage()
    }

    init(storage: any StationLibraryStorage) {
        self.storage = storage
        loadFromStorage()
    }

    func isPinned(_ station: Station) -> Bool {
        pins.contains { $0.id == station.id }
    }

    func togglePin(_ station: Station) {
        if let index = pins.firstIndex(where: { $0.id == station.id }) {
            pins.remove(at: index)
        } else {
            pins.append(station)
        }
        persist()
    }

    func movePins(from source: IndexSet, to destination: Int) {
        let validIndices = source.filter { pins.indices.contains($0) }.sorted()
        guard !validIndices.isEmpty else { return }

        let movedStations = validIndices.map { pins[$0] }
        for index in validIndices.reversed() { pins.remove(at: index) }
        let removedBeforeDestination = validIndices.filter { $0 < destination }.count
        let insertionIndex = min(max(0, destination - removedBeforeDestination), pins.count)
        pins.insert(contentsOf: movedStations, at: insertionIndex)
        persist()
    }

    func select(_ station: Station) {
        lastSelected = station
        persist()
    }

    func clearError() {
        errorMessage = nil
    }

    /// Explicitly replaces unreadable persisted data with an empty library.
    /// The corrupt file is kept intact unless the replacement is successfully written.
    func recoverFromCorruptStore() {
        guard !canPersist else { return }
        let previousPins = pins
        let previousSelection = lastSelected
        pins = []
        lastSelected = nil
        do {
            try saveSnapshot()
            canPersist = true
            errorMessage = nil
        } catch {
            pins = previousPins
            lastSelected = previousSelection
            errorMessage = "Could not recover the saved station library: \(error.localizedDescription)"
        }
    }

    private func loadFromStorage() {
        do {
            guard let data = try storage.read() else { return }
            let snapshot = try JSONDecoder().decode(StationLibrarySnapshot.self, from: data)
            guard snapshot.version == StationLibrarySnapshot.currentVersion else {
                throw StationLibraryStorageError.unsupportedVersion(snapshot.version)
            }
            pins = Self.uniqueStations(snapshot.pins)
            lastSelected = snapshot.lastSelected
        } catch {
            // Do not let subsequent mutations replace a file we could not decode.
            canPersist = false
            errorMessage = "The saved station library could not be read and was preserved. Recover it to start a new library. (\(error.localizedDescription))"
        }
    }

    private func persist() {
        guard canPersist else { return }
        do {
            try saveSnapshot()
            errorMessage = nil
        } catch {
            errorMessage = "Could not save the station library: \(error.localizedDescription)"
        }
    }

    private func saveSnapshot() throws {
        let snapshot = StationLibrarySnapshot(version: StationLibrarySnapshot.currentVersion, pins: pins, lastSelected: lastSelected)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try storage.write(encoder.encode(snapshot))
    }

    private static func uniqueStations(_ stations: [Station]) -> [Station] {
        var seen = Set<String>()
        return stations.filter { seen.insert($0.id).inserted }
    }

    private static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("FreeRadio", isDirectory: true)
            .appendingPathComponent("station-library-v1.json", isDirectory: false)
    }
}

struct StationLibrarySnapshot: Codable, Sendable {
    static let currentVersion = 1
    let version: Int
    let pins: [Station]
    let lastSelected: Station?
}

protocol StationLibraryStorage: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
}

struct FileStationLibraryStorage: StationLibraryStorage {
    let url: URL

    func read() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func write(_ data: Data) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

enum StationLibraryStorageError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Saved station library version \(version) is not supported."
        }
    }
}
