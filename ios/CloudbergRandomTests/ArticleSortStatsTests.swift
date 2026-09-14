import Foundation
import Testing
@testable import CloudbergRandom

struct ArticleSortStatsTests {
    private func article(_ id: String, claps: Int?, responses: Int?, published: Int64 = 0) -> Article {
        Article(title: id, subtitle: nil, url: "https://admiralcloudberg.medium.com/x-\(id)",
                wordCount: 1000, readingTime: 5, publishedAt: published, image: nil,
                claps: claps, responses: responses)
    }

    private func discussion(_ id: String, score: Int?, comments: Int?, ratio: Double? = nil) -> RedditDiscussion {
        RedditDiscussion(id: id, title: id, permalink: "https://www.reddit.com/r/CatastrophicFailure/comments/\(id)/",
                         createdAt: 0, score: score, comments: comments, upvoteRatio: ratio)
    }

    @Test func statSortsPutArticlesWithoutTheMetricLast() {
        let articles = [
            article("aaaaaaaaaaaa", claps: 10, responses: 1),
            article("bbbbbbbbbbbb", claps: nil, responses: nil),
            article("cccccccccccc", claps: 30, responses: 2),
        ]
        let stats = Dictionary(uniqueKeysWithValues: articles.map {
            ($0.postID, ArticleStats.from(article: $0, discussions: [], mediumOverride: nil))
        })
        let context = ArticleSort.Context(stats: stats, ranking: EngagementRanking(stats: stats))
        #expect(ArticleSort.mostClaps.sorted(articles, context: context).map(\.postID) == ["cccccccccccc", "aaaaaaaaaaaa", "bbbbbbbbbbbb"])
    }
}
