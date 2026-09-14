import Foundation
import Testing
@testable import CloudbergRandom

struct RedditIndexTests {
    @Test func bundledIndexCoversMostArticles() {
        let covered = ArticleStore.all.filter { !RedditIndex.discussions(for: $0).isEmpty }
        #expect(Double(covered.count) / Double(ArticleStore.all.count) > 0.9)
    }

    @Test func discussionsPointAtTheSubreddit() {
        for discussions in RedditIndex.byPostID.values {
            for discussion in discussions {
                #expect(discussion.url?.host() == "www.reddit.com")
                #expect(discussion.permalink.contains("/r/CatastrophicFailure/"))
            }
        }
    }

    @Test func decodesIndexFile() {
        let json = #"""
        {"abc123": [{"id": "x1", "title": "A post", "permalink": "https://www.reddit.com/r/CatastrophicFailure/comments/x1/a_post/", "createdAt": 1700000000}]}
        """#
        let index = RedditIndex.decode(Data(json.utf8))
        #expect(index["abc123"]?.first?.id == "x1")
        #expect(index["abc123"]?.first?.createdDate == Date(timeIntervalSince1970: 1_700_000_000))
    }
}
