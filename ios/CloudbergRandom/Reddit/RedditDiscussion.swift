import Foundation

/// A r/CatastrophicFailure post where an article was shared and discussed.
struct RedditDiscussion: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let permalink: String
    let createdAt: Int64
    /// As archived about a day and a half after posting.
    var score: Int? = nil
    var comments: Int? = nil
    var upvoteRatio: Double? = nil

    var url: URL? { URL(string: permalink) }

    var createdDate: Date { Date(timeIntervalSince1970: TimeInterval(createdAt)) }
}

/// Bundled index of discussions per article (see scripts/update-reddit-index.py).
enum RedditIndex {
    static let subreddit = "r/CatastrophicFailure"

    /// Keyed by Medium post id; the most-upvoted post comes first.
    static let byPostID: [String: [RedditDiscussion]] = load(from: Bundle.main)

    static func discussions(for article: Article) -> [RedditDiscussion] {
        byPostID[article.postID] ?? []
    }

    static func load(from bundle: Bundle) -> [String: [RedditDiscussion]] {
        guard let file = bundle.url(forResource: "reddit", withExtension: "json"),
              let data = try? Data(contentsOf: file) else { return [:] }
        return decode(data)
    }

    static func decode(_ data: Data) -> [String: [RedditDiscussion]] {
        (try? JSONDecoder().decode([String: [RedditDiscussion]].self, from: data)) ?? [:]
    }
}
