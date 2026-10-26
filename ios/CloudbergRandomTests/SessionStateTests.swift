import Foundation
import Testing
@testable import CloudbergRandom

@MainActor
struct SessionStateTests {
    private func temporaryState() -> (SessionState, UserDefaults) {
        let suite = "session.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (SessionState(defaults: defaults), defaults)
    }

    @Test func startsOnTheRandomTabWithNothingOpen() {
        let (session, _) = temporaryState()
        #expect(session.tab == .random)
        #expect(session.randomPostID == nil)
        #expect(session.openPostID(for: .articles) == nil)
        #expect(session.listTopPostID == nil)
        #expect(session.listSearch.isEmpty)
    }

    @Test func everythingOnScreenSurvivesARelaunch() {
        let (session, defaults) = temporaryState()
        session.tab = .articles
        session.randomPostID = "aaaaaaaaaaaa"
        session.setOpenPostID("bbbbbbbbbbbb", for: .articles)
        session.listTopPostID = "cccccccccccc"
        session.listSearch = "turkish"
        session.flush()

        let relaunched = SessionState(defaults: defaults)
        #expect(relaunched.tab == .articles)
        #expect(relaunched.randomPostID == "aaaaaaaaaaaa")
        #expect(relaunched.openPostID(for: .articles) == "bbbbbbbbbbbb")
        #expect(relaunched.openPostID(for: .random) == nil)
        #expect(relaunched.listTopPostID == "cccccccccccc")
        #expect(relaunched.listSearch == "turkish")
    }

    @Test func closingAnArticleClearsIt() {
        let (session, defaults) = temporaryState()
        session.setOpenPostID("bbbbbbbbbbbb", for: .random)
        session.setOpenPostID(nil, for: .random)
        session.flush()

        #expect(SessionState(defaults: defaults).openPostID(for: .random) == nil)
    }

    @Test func articlesCanBeLookedUpByPostID() throws {
        let article = try #require(ArticleStore.all.first)
        #expect(ArticleStore.article(postID: article.postID) == article)
        #expect(ArticleStore.article(postID: "nosucharticle") == nil)
    }
}
