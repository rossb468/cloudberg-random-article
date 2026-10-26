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
    /// When each of those was last read, for ordering what's in progress.
    private(set) var readAtByPostID: [String: Date] = [:]

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
        progressByPostID = scanned.progress.merging(progressByPostID) { _, newer in newer }
        readAtByPostID = scanned.readAt.merging(readAtByPostID) { _, newer in newer }
    }

    private nonisolated static func scanProgress(
        in directory: URL
    ) async -> (progress: [String: Double], readAt: [String: Date]) {
        await Task.detached(priority: .utility) {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            var progress: [String: Double] = [:]
            var readAt: [String: Date] = [:]
            for file in files where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file),
                      let state = try? JSONDecoder().decode(ReadingState.self, from: data) else { continue }
                let postID = file.deletingPathExtension().lastPathComponent
                progress[postID] = state.progress
                readAt[postID] = state.updatedAt
            }
            return (progress, readAt)
        }.value
    }

    /// Articles you've started but haven't finished, most recently read first.
    func inProgress(from articles: [Article], finishedAbove: Double = 0.97) -> [Article] {
        articles
            .filter { article in
                guard let progress = progressByPostID[article.postID] else { return false }
                return progress > 0.02 && progress < finishedAbove
            }
            .sorted { lhs, rhs in
                (readAtByPostID[lhs.postID] ?? .distantPast) > (readAtByPostID[rhs.postID] ?? .distantPast)
            }
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
        readAtByPostID[postID] = state.updatedAt ?? .now
        try? JSONEncoder().encode(state).write(to: file(for: postID), options: .atomic)
    }

    /// Forgets every saved position and bookmark.
    func clearAll() {
        cache = [:]
        progressByPostID = [:]
        readAtByPostID = [:]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func file(for postID: String) -> URL {
        directory.appendingPathComponent("\(postID).json")
    }
}
