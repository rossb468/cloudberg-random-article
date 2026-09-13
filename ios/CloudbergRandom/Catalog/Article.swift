import Foundation

struct Article: Codable, Identifiable {
    let title: String
    let subtitle: String?
    let url: String
    let wordCount: Int?
    let readingTime: Double?
    let publishedAt: Int64?
    let image: String?

    var id: String { url }

    /// Medium's post id, the hex suffix of the article URL.
    var postID: String {
        url.range(of: "[0-9a-f]{10,12}$", options: .regularExpression).map { String(url[$0]) } ?? url
    }

    var webURL: URL? { URL(string: url) }

    var publishedDate: Date? {
        publishedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) }
    }

    var coverImageURL: URL? {
        guard let image, !image.isEmpty else { return nil }
        return URL(string: "https://miro.medium.com/v2/resize:fit:1200/\(image)")
    }

    var publishedDateText: String? {
        publishedDate?.formatted(date: .abbreviated, time: .omitted)
    }

    var readingTimeText: String? {
        guard let readingTime else { return nil }
        return "\(Int(readingTime.rounded())) min read"
    }
}

enum ArticleStore {
    static let all: [Article] = {
        guard let fileURL = Bundle.main.url(forResource: "articles", withExtension: "json"),
              let data = try? Data(contentsOf: fileURL),
              let articles = try? JSONDecoder().decode([Article].self, from: data)
        else { return [] }
        return articles
    }()
}
