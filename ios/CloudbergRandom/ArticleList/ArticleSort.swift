import Foundation

enum ArticleSort: String, CaseIterable, Identifiable {
    case newest, oldest, title, longest, shortest
    case mostEngaging, mostClaps, topOnReddit, mostDiscussed

    /// Engagement numbers the stat sorts read.
    struct Context: Equatable {
        var stats: [String: ArticleStats] = [:]
        var ranking = EngagementRanking(stats: [:])

        static let none = Context()
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .title: "Title"
        case .longest: "Longest"
        case .shortest: "Shortest"
        case .mostEngaging: "Most Engaging"
        case .mostClaps: "Most Claps"
        case .topOnReddit: "Top on Reddit"
        case .mostDiscussed: "Most Discussed"
        }
    }

    var systemImage: String {
        switch self {
        case .newest: "calendar"
        case .oldest: "calendar"
        case .title: "textformat"
        case .longest: "text.alignleft"
        case .shortest: "text.alignleft"
        case .mostEngaging: "flame"
        case .mostClaps: "hands.clap"
        case .topOnReddit: "arrow.up"
        case .mostDiscussed: "bubble.left.and.bubble.right"
        }
    }

    /// Date sorts read best split into one section per year.
    var groupsByYear: Bool { self == .newest || self == .oldest }

    var isEngagement: Bool {
        switch self {
        case .mostEngaging, .mostClaps, .topOnReddit, .mostDiscussed: true
        default: false
        }
    }

    func sorted(_ articles: [Article], context: Context = .none) -> [Article] {
        switch self {
        case .newest: articles.sorted { ($0.publishedAt ?? 0) > ($1.publishedAt ?? 0) }
        case .oldest: articles.sorted { ($0.publishedAt ?? 0) < ($1.publishedAt ?? 0) }
        case .title: articles.sorted { $0.sortableTitle.localizedStandardCompare($1.sortableTitle) == .orderedAscending }
        case .longest: articles.sorted { ($0.wordCount ?? 0) > ($1.wordCount ?? 0) }
        case .shortest: articles.sorted { ($0.wordCount ?? 0) < ($1.wordCount ?? 0) }
        case .mostEngaging: Self.descending(articles) { context.ranking.score(for: $0.postID) }
        case .mostClaps: Self.descending(articles) { context.stats[$0.postID]?.claps.map(Double.init) }
        case .topOnReddit: Self.descending(articles) { context.stats[$0.postID]?.redditScore.map(Double.init) }
        case .mostDiscussed: Self.descending(articles) { context.stats[$0.postID]?.discussionCount.map(Double.init) }
        }
    }

    /// Highest first; articles without the number last, newest first among ties.
    private static func descending(_ articles: [Article], by value: (Article) -> Double?) -> [Article] {
        articles
            .map { (article: $0, value: value($0)) }
            .sorted { lhs, rhs in
                switch (lhs.value, rhs.value) {
                case let (l?, r?) where l != r: l > r
                case (_?, nil): true
                case (nil, _?): false
                default: (lhs.article.publishedAt ?? 0) > (rhs.article.publishedAt ?? 0)
                }
            }
            .map(\.article)
    }
}

extension Article {
    /// Title without a leading "The"/"A"/"An", for alphabetical sorting.
    var sortableTitle: String {
        for article in ["The ", "A ", "An "] where title.hasPrefix(article) {
            return String(title.dropFirst(article.count))
        }
        return title
    }

    func matches(search query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [title, subtitle ?? ""].contains {
            $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
