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

    var coverImageURL: URL? {
        guard let image, !image.isEmpty else { return nil }
        return URL(string: "https://miro.medium.com/v2/resize:fit:1200/\(image)")
    }

    var publishedDateText: String? {
        guard let publishedAt else { return nil }
        let date = Date(timeIntervalSince1970: Double(publishedAt) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
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
