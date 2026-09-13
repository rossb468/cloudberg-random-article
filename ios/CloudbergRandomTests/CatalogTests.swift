import Foundation
import Testing
@testable import CloudbergRandom

struct CatalogTests {
    @Test func bundledCatalogLoads() {
        #expect(ArticleStore.all.count > 200)
    }

    @Test func postIDComesFromURLSuffix() {
        let article = Article(
            title: "The near crash of Air Canada flight 759",
            subtitle: nil,
            url: "https://admiralcloudberg.medium.com/the-near-crash-of-air-canada-flight-759-c61094867d45",
            wordCount: nil, readingTime: nil, publishedAt: nil, image: nil
        )
        #expect(article.postID == "c61094867d45")
    }

    @Test func postIDsCanBeShorterThanTwelveDigits() {
        let article = Article(
            title: "All the President’s Men",
            subtitle: nil,
            url: "https://admiralcloudberg.medium.com/all-the-presidents-men-the-death-of-lech-kaczyński-590a3977f",
            wordCount: nil, readingTime: nil, publishedAt: nil, image: nil
        )
        #expect(article.postID == "590a3977f")
    }
}
