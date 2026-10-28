import XCTest
@testable import FreeRadio

final class LibraryTests: XCTestCase {
    @MainActor
    func testPinsCanBeSavedReorderedRemovedAndRestored() throws {
        let storage = MemoryLibraryStorage()
        let library = StationLibrary(storage: storage)
        let a = station("a")
        let b = station("b")
        let c = station("c")

        library.togglePin(a)
        library.togglePin(b)
        library.togglePin(c)
        library.movePins(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(library.pins.map(\.id), ["c", "a", "b"])
        library.togglePin(a)
        XCTAssertEqual(library.pins.map(\.id), ["c", "b"])

        let restored = StationLibrary(storage: storage)
        XCTAssertEqual(restored.pins.map(\.id), ["c", "b"])
        XCTAssertNil(restored.lastSelected)
    }

    @MainActor
    func testSelectionIsIndependentOfPinMembershipAndRestoresWithoutAutoplayState() {
        let storage = MemoryLibraryStorage()
        let library = StationLibrary(storage: storage)
        let selected = station("selected")
        library.select(selected)

        XCTAssertFalse(library.isPinned(selected))
        let restored = StationLibrary(storage: storage)
        XCTAssertEqual(restored.lastSelected, selected)
        XCTAssertTrue(restored.pins.isEmpty)
    }

    @MainActor
    func testDecodeFailurePreservesFileUntilExplicitRecovery() throws {
        let corruptData = Data("not valid json".utf8)
        let storage = MemoryLibraryStorage(data: corruptData)
        let library = StationLibrary(storage: storage)

        XCTAssertNotNil(library.errorMessage)
        library.togglePin(station("a"))
        XCTAssertEqual(try storage.read(), corruptData)

        library.recoverFromCorruptStore()
        XCTAssertNil(library.errorMessage)
        XCTAssertFalse(try XCTUnwrap(storage.read()).isEmpty)
        let restored = StationLibrary(storage: storage)
        XCTAssertTrue(restored.pins.isEmpty)
        XCTAssertNil(restored.lastSelected)
    }

    @MainActor
    func testWriteFailureIsReported() {
        let storage = MemoryLibraryStorage()
        storage.shouldFailWrite = true
        let library = StationLibrary(storage: storage)
        library.togglePin(station("a"))

        XCTAssertEqual(library.pins.map(\.id), ["a"])
        XCTAssertTrue(library.errorMessage?.contains("Could not save") == true)
    }

    private func station(_ id: String) -> Station {
        Station(id: id, name: "Station \(id)", streamURL: URL(string: "https://example.com/\(id)")!)
    }
}

private final class MemoryLibraryStorage: StationLibraryStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    var shouldFailWrite = false

    init(data: Data? = nil) { self.data = data }

    func read() throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func write(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !shouldFailWrite else { throw TestStorageError.writeFailed }
        self.data = data
    }
}

private enum TestStorageError: Error {
    case writeFailed
}
