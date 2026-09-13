import SwiftUI

struct ArticleListView: View {
    @Environment(\.openArticle) private var openArticle
    @AppStorage("articleList.sort") private var sort: ArticleSort = .newest
    @State private var searchText = ""

    private let articles = ArticleStore.all

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.title) { section in
                    Section {
                        ForEach(section.articles) { article in
                            Button {
                                openArticle(article)
                            } label: {
                                ArticleRow(article: article)
                            }
                            .listRowBackground(Theme.background)
                            .listRowSeparatorTint(Theme.border)
                        }
                    } header: {
                        if let title = section.title {
                            Text(title)
                                .font(.subheadline.bold())
                                .foregroundColor(Theme.accent)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .navigationTitle("Articles")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search \(articles.count) articles")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(ArticleSort.allCases) { option in
                                Label(option.label, systemImage: option.systemImage).tag(option)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
        }
    }

    private var filtered: [Article] {
        sort.sorted(articles.filter { $0.matches(search: searchText) })
    }

    private var sections: [(title: String?, articles: [Article])] {
        let articles = filtered
        guard sort.groupsByYear else { return [(nil, articles)] }
        var result: [(title: String?, articles: [Article])] = []
        for article in articles {
            let year = article.publishedDate.map { String(Calendar.current.component(.year, from: $0)) } ?? "Undated"
            if result.last?.title == year {
                result[result.count - 1].articles.append(article)
            } else {
                result.append((year, [article]))
            }
        }
        return result
    }
}

struct ArticleRow: View {
    let article: Article

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: MediumImage.url(id: article.image ?? "", width: 200)) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Theme.card.overlay(Image(systemName: "airplane").foregroundColor(Theme.border))
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if let date = article.publishedDateText { Text(date) }
                    if let readingTime = article.readingTimeText { Text("·"); Text(readingTime) }
                }
                .font(.caption)
                .foregroundColor(Theme.textDim)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview {
    ArticleListView()
        .preferredColorScheme(.dark)
}
