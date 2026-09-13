import Foundation

enum ArticleSort: String, CaseIterable, Identifiable {
    case newest, oldest, title, longest, shortest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .title: "Title"
        case .longest: "Longest"
        case .shortest: "Shortest"
        }
    }

    var systemImage: String {
        switch self {
        case .newest: "calendar"
        case .oldest: "calendar"
        case .title: "textformat"
        case .longest: "text.alignleft"
        case .shortest: "text.alignleft"
        }
    }

    /// Date sorts read best split into one section per year.
    var groupsByYear: Bool { self == .newest || self == .oldest }

    func sorted(_ articles: [Article]) -> [Article] {
        switch self {
        case .newest: articles.sorted { ($0.publishedAt ?? 0) > ($1.publishedAt ?? 0) }
        case .oldest: articles.sorted { ($0.publishedAt ?? 0) < ($1.publishedAt ?? 0) }
        case .title: articles.sorted { $0.sortableTitle.localizedStandardCompare($1.sortableTitle) == .orderedAscending }
        case .longest: articles.sorted { ($0.wordCount ?? 0) > ($1.wordCount ?? 0) }
        case .shortest: articles.sorted { ($0.wordCount ?? 0) < ($1.wordCount ?? 0) }
        }
    }
}

extension Article {
    /// Title without a leading "The"/"A"/"An", for alphabetical sorting.
    var sortableTitle: String {
        for article in ["The ", "A ", "An "] where title.hasPrefix(article) {
            return String(title.dropFirst(article.count))
        }
        return title
    }

    func matches(search query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [title, subtitle ?? ""].contains {
            $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
