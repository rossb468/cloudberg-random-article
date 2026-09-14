import Foundation

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
final class ReadingStateStore {
    static let shared = ReadingStateStore()

    private let directory: URL
    private var cache: [String: ReadingState] = [:]

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReadingState", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
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
        try? JSONEncoder().encode(state).write(to: file(for: postID), options: .atomic)
    }

    private func file(for postID: String) -> URL {
        directory.appendingPathComponent("\(postID).json")
    }
}
