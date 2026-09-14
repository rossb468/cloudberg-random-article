import Foundation
import Testing
@testable import CloudbergRandom

struct EngagementTests {
    private func article(_ id: String, claps: Int?, responses: Int?, published: Int64 = 0) -> Article {
        Article(title: id, subtitle: nil, url: "https://admiralcloudberg.medium.com/x-\(id)",
                wordCount: 1000, readingTime: 5, publishedAt: published, image: nil,
                claps: claps, responses: responses)
    }

    private func discussion(_ id: String, score: Int?, comments: Int?, ratio: Double? = nil) -> RedditDiscussion {
        RedditDiscussion(id: id, title: id, permalink: "https://www.reddit.com/r/CatastrophicFailure/comments/\(id)/",
                         createdAt: 0, score: score, comments: comments, upvoteRatio: ratio)
    }

    @Test func statsCombineSnapshotRedditAndOverrides() {
        let a = article("aaaaaaaaaaaa", claps: 100, responses: 4)
        let stats = ArticleStats.from(
            article: a,
            discussions: [discussion("r1", score: 50, comments: 10, ratio: 0.9), discussion("r2", score: 900, comments: 30, ratio: 0.97)],
            mediumOverride: MediumEngagement(claps: 150, responses: 6, updatedAt: .now)
        )
        #expect(stats.claps == 150)
        #expect(stats.mediumResponses == 6)
        #expect(stats.redditScore == 900)
        #expect(stats.redditUpvoteRatio == 0.97)
        #expect(stats.redditComments == 40)
        #expect(stats.discussionCount == 46)
    }

    @Test func missingMetricsStayMissing() {
        let stats = ArticleStats.from(article: article("bbbbbbbbbbbb", claps: nil, responses: nil), discussions: [], mediumOverride: nil)
        #expect(stats.redditScore == nil)
        #expect(stats.discussionCount == nil)
    }

    @Test func rankingAveragesPercentilesAcrossAvailableMetrics() {
        let ranking = EngagementRanking(stats: [
            "top": ArticleStats(claps: 5000, mediumResponses: 50, redditScore: 9000, redditComments: 700),
            "mid": ArticleStats(claps: 3000, mediumResponses: 20, redditScore: 2000, redditComments: 100),
            "low": ArticleStats(claps: 1000, mediumResponses: 5, redditScore: 100, redditComments: 10),
            // No Reddit post: judged on the metrics it has.
            "old": ArticleStats(claps: 4000, mediumResponses: 30),
        ])
        #expect(ranking.overallRank(of: "top") == 1)
        #expect(ranking.overallRank(of: "low") == 4)
        #expect(ranking.rank(of: "old", by: .claps) == 2)
        #expect(ranking.rank(of: "old", by: .redditScore) == nil)
        #expect((ranking.score(for: "top") ?? 0) == 1)
    }

    @Test func tiesShareARank() {
        let ranking = EngagementRanking(stats: [
            "a": ArticleStats(claps: 10), "b": ArticleStats(claps: 10), "c": ArticleStats(claps: 5),
        ])
        #expect(ranking.rank(of: "a", by: .claps) == 1)
        #expect(ranking.rank(of: "b", by: .claps) == 1)
        #expect(ranking.rank(of: "c", by: .claps) == 3)
    }
}
