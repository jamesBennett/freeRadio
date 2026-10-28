import Foundation

/// Extracts `StreamTitle` from a SHOUTcast/Icecast byte stream whose audio is
/// interleaved with metadata blocks every `metaInterval` bytes.
struct ICYMetadataReader {
    let metaInterval: Int
    private var audioRemaining: Int
    private var blockRemaining: Int?
    private var block = Data()
    private(set) var latestTitle: String?
    private var slotsRead = 0

    init(metaInterval: Int) {
        self.metaInterval = metaInterval
        audioRemaining = metaInterval
    }

    /// Ad-inserting servers open each connection with a placeholder title and send
    /// the real one a slot later, so a title counts only once two slots are read.
    var settledTitle: String? { slotsRead >= 2 ? latestTitle : nil }

    /// Returns a title when a metadata block carrying a non-empty one completes.
    mutating func consume(_ byte: UInt8) -> String? {
        if audioRemaining > 0 {
            audioRemaining -= 1
            return nil
        }
        guard let remaining = blockRemaining else {
            // Length byte: block size in 16-byte units. Zero means no metadata this interval.
            if byte == 0 {
                audioRemaining = metaInterval
                slotsRead += 1
            } else {
                blockRemaining = Int(byte) * 16
                block.removeAll(keepingCapacity: true)
            }
            return nil
        }
        block.append(byte)
        guard remaining > 1 else {
            blockRemaining = nil
            audioRemaining = metaInterval
            slotsRead += 1
            let title = Self.streamTitle(in: block)
            if let title { latestTitle = title }
            return title
        }
        blockRemaining = remaining - 1
        return nil
    }

    static func streamTitle(in block: Data) -> String? {
        let trimmed = block.prefix { $0 != 0 }
        guard let text = String(data: trimmed, encoding: .utf8) ?? String(data: trimmed, encoding: .isoLatin1),
              let start = text.range(of: "StreamTitle='") else { return nil }
        let rest = text[start.upperBound...]
        // Titles may contain apostrophes, so the field ends at `';`, not the first quote.
        let end = rest.range(of: "';")?.lowerBound ?? rest.lastIndex(of: "'") ?? rest.endIndex
        let title = rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}

/// AVFoundation does not request in-band ICY metadata for progressive streams, so
/// this briefly opens a separate connection that asks for it, reads one title and
/// disconnects, repeating while the station plays. Generic for any ICY server.
@MainActor
final class ICYTitlePoller {
    private let session: URLSession
    private let interval: Duration
    private var task: Task<Void, Never>?

    init(interval: Duration = .seconds(20)) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration)
        self.interval = interval
    }

    nonisolated static func supports(_ url: URL) -> Bool {
        url.pathExtension.lowercased() != "m3u8"
    }

    func start(url: URL, onTitle: @escaping @MainActor (String) -> Void) {
        stop()
        guard Self.supports(url) else { return }
        task = Task { [session, interval] in
            var failures = 0
            while !Task.isCancelled, failures < 3 {
                switch await Self.fetchTitle(from: url, session: session) {
                case .unsupported:
                    return
                case .title(let title):
                    failures = 0
                    guard !Task.isCancelled else { return }
                    onTitle(title)
                case .none:
                    failures += 1
                }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private enum FetchResult {
        case title(String)
        case unsupported
    }

    private nonisolated static func fetchTitle(from url: URL, session: URLSession) async -> FetchResult? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        request.setValue("FreeRadio/0.1", forHTTPHeaderField: "User-Agent")
        guard let (bytes, response) = try? await session.bytes(for: request) else { return nil }
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        guard let metaInterval = http.value(forHTTPHeaderField: "icy-metaint").flatMap(Int.init),
              (1...512_000).contains(metaInterval) else { return .unsupported }

        var reader = ICYMetadataReader(metaInterval: metaInterval)
        // A few intervals is enough: servers send the current title in the first slots.
        let byteLimit = 4 * (metaInterval + 4_081)
        var count = 0
        do {
            for try await byte in bytes {
                _ = reader.consume(byte)
                if let title = reader.settledTitle { return .title(title) }
                count += 1
                if count >= byteLimit || Task.isCancelled { break }
            }
        } catch {}
        return Task.isCancelled ? nil : reader.latestTitle.map(FetchResult.title)
    }
}
