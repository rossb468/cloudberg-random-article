import Foundation
import Testing
@testable import CloudbergRandom

struct ArticleSortTests {
    private func article(_ title: String, published: Int64, words: Int, subtitle: String? = nil) -> Article {
        Article(title: title, subtitle: subtitle, url: "https://example.com/\(published)",
                wordCount: words, readingTime: nil, publishedAt: published, image: nil)
    }

    private var sample: [Article] {
        [
            article("The Crash of Turkish Airlines flight 1951", published: 2, words: 3000),
            article("A Long Night in Coventry", published: 3, words: 9000),
            article("Matter Over Mind", published: 1, words: 6000, subtitle: "Turkish Airlines flight 6491"),
        ]
    }

    @Test func sortsByDate() {
        #expect(ArticleSort.newest.sorted(sample).map(\.publishedAt) == [3, 2, 1])
        #expect(ArticleSort.oldest.sorted(sample).map(\.publishedAt) == [1, 2, 3])
    }

    @Test func titleSortIgnoresLeadingArticles() {
        #expect(ArticleSort.title.sorted(sample).map(\.title) == [
            "The Crash of Turkish Airlines flight 1951",
            "A Long Night in Coventry",
            "Matter Over Mind",
        ])
    }

    @Test func sortsByLength() {
        #expect(ArticleSort.longest.sorted(sample).map(\.wordCount) == [9000, 6000, 3000])
    }

    @Test func searchMatchesTitleAndSubtitle() {
        #expect(sample.filter { $0.matches(search: "turkish") }.count == 2)
        #expect(sample.filter { $0.matches(search: "coventry") }.count == 1)
        #expect(sample.filter { $0.matches(search: "  ") }.count == 3)
    }
}
