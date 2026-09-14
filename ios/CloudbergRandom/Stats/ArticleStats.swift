import Foundation

/// Engagement numbers for one article from Medium and Reddit.
struct ArticleStats: Equatable {
    var claps: Int?
    var mediumResponses: Int?
    /// When the Medium numbers were read from Medium by the app; nil means
    /// they come from the bundled catalog snapshot.
    var mediumUpdatedAt: Date?

    /// Score of the most-upvoted r/CatastrophicFailure post for the article.
    var redditScore: Int?
    var redditUpvoteRatio: Double?
    /// Comments across all of the article's Reddit posts.
    var redditComments: Int?

    /// Conversation on both sites combined.
    var discussionCount: Int? {
        guard mediumResponses != nil || redditComments != nil else { return nil }
        return (mediumResponses ?? 0) + (redditComments ?? 0)
    }

    static func from(article: Article, discussions: [RedditDiscussion], mediumOverride: MediumEngagement?) -> ArticleStats {
        let scored = discussions.compactMap(\.score)
        let top = discussions.max { ($0.score ?? 0) < ($1.score ?? 0) }
        let comments = discussions.compactMap(\.comments)
        return ArticleStats(
            claps: mediumOverride?.claps ?? article.claps,
            mediumResponses: mediumOverride?.responses ?? article.responses,
            mediumUpdatedAt: mediumOverride?.updatedAt,
            redditScore: scored.isEmpty ? nil : scored.max(),
            redditUpvoteRatio: top?.upvoteRatio,
            redditComments: comments.isEmpty ? nil : comments.reduce(0, +)
        )
    }
}

/// Medium numbers read at runtime, newer than the catalog snapshot.
struct MediumEngagement: Codable, Equatable {
    var claps: Int
    var responses: Int
    var updatedAt: Date
}

/// Ranks articles by how much engagement they drew, overall and per metric.
struct EngagementRanking: Equatable {
    enum Metric: CaseIterable {
        case claps, redditScore, discussion

        func value(_ stats: ArticleStats) -> Int? {
            switch self {
            case .claps: stats.claps
            case .redditScore: stats.redditScore
            case .discussion: stats.discussionCount
            }
        }
    }

    /// 0...1 per article: the average of its percentile on each metric it has.
    /// Percentiles rather than raw numbers so claps (thousands) don't drown
    /// out comment counts (tens), and so older articles with no Reddit post
    /// aren't penalized for a missing metric.
    let scores: [String: Double]
    private let ranks: [Metric: [String: Int]]
    let count: Int

    init(stats: [String: ArticleStats]) {
        count = stats.count
        var percentiles: [String: [Double]] = [:]
        var ranks: [Metric: [String: Int]] = [:]
        for metric in Metric.allCases {
            var values: [(id: String, value: Int)] = []
            for (id, stat) in stats {
                if let value = metric.value(stat) { values.append((id, value)) }
            }
            values.sort { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.id < rhs.id
            }
            guard values.count > 1 else { continue }
            var metricRanks: [String: Int] = [:]
            var tieRank = 1
            for (position, entry) in values.enumerated() {
                // Ties share the best rank.
                if position > 0 && values[position - 1].value != entry.value { tieRank = position + 1 }
                metricRanks[entry.id] = tieRank
                percentiles[entry.id, default: []].append(1 - Double(position) / Double(values.count - 1))
            }
            ranks[metric] = metricRanks
        }
        scores = percentiles.mapValues { $0.reduce(0, +) / Double($0.count) }
        self.ranks = ranks
    }

    func score(for postID: String) -> Double? { scores[postID] }

    /// 1-based rank among articles that have the metric.
    func rank(of postID: String, by metric: Metric) -> Int? { ranks[metric]?[postID] }

    func overallRank(of postID: String) -> Int? {
        guard let score = scores[postID] else { return nil }
        return scores.values.filter { $0 > score }.count + 1
    }
}
