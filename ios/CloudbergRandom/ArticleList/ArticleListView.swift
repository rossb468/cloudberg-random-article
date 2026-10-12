import SwiftUI

struct ArticleListView: View {
    @Environment(\.openArticle) private var openArticle
    @AppStorage("articleList.sort") private var sort: ArticleSort = .newest
    @State private var searchText = ""
    @State private var webPage: IdentifiableURL?
    @State private var statsArticle: Article?
    @Environment(EngagementStore.self) private var engagement

    private let articles = ArticleStore.all

    var body: some View {
        List {
            ForEach(sections, id: \.title) { section in
                Section {
                    ForEach(section.articles) { article in
                        Button {
                            openArticle(article)
                        } label: {
                            ArticleRow(article: article)
                        }
                        .swipeActions(edge: .trailing) { offlineSwipeAction(for: article) }
                        .contextMenu {
                            Button("Read", systemImage: "book") { openArticle(article) }
                            RedditDiscussionMenuItems(article: article) { webPage = IdentifiableURL(url: $0) }
                            Button("Engagement Stats", systemImage: "chart.bar") { statsArticle = article }
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
        .sheet(item: $webPage) { page in
            SafariView(url: page.url).ignoresSafeArea()
        }
        .sheet(item: $statsArticle) { article in
            ArticleStatsView(article: article)
                .presentationDetents([.medium, .large])
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if engagement.isRefreshing {
                    HStack(spacing: 6) {
                        ProgressView()
                        Text("\(engagement.refreshProgress.done)/\(engagement.refreshProgress.total)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(Theme.textDim)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Updating Medium stats")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(ArticleSort.allCases.filter { !$0.isEngagement }) { option in
                            Label(option.label, systemImage: option.systemImage).tag(option)
                        }
                        Section("Engagement") {
                            ForEach(ArticleSort.allCases.filter(\.isEngagement)) { option in
                                Label(option.label, systemImage: option.systemImage).tag(option)
                            }
                        }
                    }
                    Section {
                        if engagement.isRefreshing {
                            Button("Stop Updating Medium Stats", systemImage: "stop.circle") {
                                engagement.cancelRefresh()
                            }
                        } else {
                            Button("Update Medium Stats", systemImage: "arrow.clockwise") {
                                engagement.refreshMediumStats()
                            }
                        }
                    } footer: {
                        Text("Re-reads every article page from Medium for current claps and responses.")
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }

    @Environment(OfflineLibrary.self) private var library

    @ViewBuilder
    private func offlineSwipeAction(for article: Article) -> some View {
        if library.isAvailableOffline(article) {
            Button("Remove Download", systemImage: "trash", role: .destructive) { library.remove(article) }
        } else {
            Button("Download", systemImage: "arrow.down.circle") { library.download(article) }
                .tint(Theme.accent)
        }
    }

    private var filtered: [Article] {
        sort.sorted(articles.filter { $0.matches(search: searchText) }, context: engagement.sortContext)
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
    @Environment(EngagementStore.self) private var engagement

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
                ArticleStatsLine(stats: engagement.stats(for: article))
            }
            Spacer(minLength: 0)
            OfflineStatusIcon(article: article)
                .font(.title3)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview {
    ArticleListView()
        .environment(OfflineLibrary.shared)
        .environment(EngagementStore.shared)
        .preferredColorScheme(.dark)
}
