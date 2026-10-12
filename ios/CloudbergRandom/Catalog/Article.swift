import Foundation

struct Article: Codable, Identifiable, Hashable {
    let title: String
    let subtitle: String?
    let url: String
    let wordCount: Int?
    let readingTime: Double?
    let publishedAt: Int64?
    let image: String?
    /// Medium engagement in the bundled catalog snapshot.
    var claps: Int? = nil
    var responses: Int? = nil

    var id: String { url }

    /// Medium's post id: the hex suffix after the slug's last hyphen (8–12 digits).
    var postID: String {
        url.range(of: "-[0-9a-f]{8,12}$", options: .regularExpression).map { String(url[$0].dropFirst()) } ?? url
    }

    var webURL: URL? { URL(string: url) }

    var publishedDate: Date? {
        publishedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) }
    }

    var coverImageURL: URL? {
        MediumImage.url(id: image ?? "", width: 1200)
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
