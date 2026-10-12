import Foundation
import Observation

struct Bookmark: Codable, Identifiable, Equatable {
    var id = UUID()
    let blockID: String
    var excerpt: String
    var createdAt = Date()
}

/// Per-article reading position and bookmarks.
struct ReadingState: Codable, Equatable {
    var blockID: String?
    var progress: Double = 0
    var updatedAt: Date?
    var bookmarks: [Bookmark] = []
}

/// Stores `ReadingState` as one small JSON file per article, separate from the
/// offline library so removing downloads keeps positions and bookmarks.
@MainActor
@Observable
final class ReadingStateStore {
    static let shared = ReadingStateStore()

    /// How far through each article you are, so lists can show progress
    /// without reading a file per row. Filled in from disk after launch.
    private(set) var progressByPostID: [String: Double] = [:]

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var cache: [String: ReadingState] = [:]

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReadingState", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        Task { await reloadProgress() }
    }

    func progress(for postID: String) -> Double? {
        progressByPostID[postID]
    }

    /// Reads every saved position off the main actor.
    func reloadProgress() async {
        let scanned = await Self.scanProgress(in: directory)
        // Anything saved while the scan ran is newer than what it found.
        progressByPostID = scanned.merging(progressByPostID) { _, newer in newer }
    }

    private nonisolated static func scanProgress(in directory: URL) async -> [String: Double] {
        await Task.detached(priority: .utility) {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            var progress: [String: Double] = [:]
            for file in files where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file),
                      let state = try? JSONDecoder().decode(ReadingState.self, from: data) else { continue }
                progress[file.deletingPathExtension().lastPathComponent] = state.progress
            }
            return progress
        }.value
    }

    func state(for postID: String) -> ReadingState {
        if let cached = cache[postID] { return cached }
        let state = (try? Data(contentsOf: file(for: postID)))
            .flatMap { try? JSONDecoder().decode(ReadingState.self, from: $0) } ?? ReadingState()
        cache[postID] = state
        return state
    }

    func save(_ state: ReadingState, for postID: String) {
        guard cache[postID] != state else { return }
        cache[postID] = state
        progressByPostID[postID] = state.progress
        try? JSONEncoder().encode(state).write(to: file(for: postID), options: .atomic)
    }

    private func file(for postID: String) -> URL {
        directory.appendingPathComponent("\(postID).json")
    }
}
