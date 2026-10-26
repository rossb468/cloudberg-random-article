import SwiftUI

struct ArticleListView: View {
    @Environment(\.openArticle) private var openArticle
    @AppStorage("articleList.sort") private var sort: ArticleSort = .newest
    @State private var searchText = SessionState.shared.listSearch
    /// The filtered, sorted list, kept in state so scrolling doesn't re-sort
    /// the catalog every time a row appears.
    @State private var ordered: [Article] = []
    /// Rows currently alive in the list, and how far each one's top sits from
    /// the top of the list when the system reports it (iOS 18+). The list keeps
    /// a row or two alive beyond the screen, so the offsets are what make the
    /// remembered row the one actually at the top.
    @State private var visibleIDs: Set<Article.ID> = []
    @State private var rowOffsets: [Article.ID: CGFloat] = [:]
    /// Where the visible area starts inside the list: under the navigation bar,
    /// not at the list's own top edge.
    @State private var topInset: CGFloat = 0
    @State private var restoredScroll = false
    private let session = SessionState.shared
    @State private var webPage: IdentifiableURL?
    @State private var statsArticle: Article?
    @State private var showingDownloads = false
    @Environment(AppSettings.self) private var appSettings
    @Environment(ReadingStateStore.self) private var reading
    @Environment(EngagementStore.self) private var engagement

    private let articles = ArticleStore.all
    private static let listSpace = "articleList"
    private static let inProgressTitle = "Continue Reading"

    /// Only when the whole list is on screen: a search is its own answer.
    private var inProgressArticles: [Article] {
        guard appSettings.showInProgressSection, searchText.isEmpty else { return [] }
        return reading.inProgress(from: articles)
    }


    var body: some View {
        ScrollViewReader { proxy in
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
                                ArticleActionsMenu(
                                    article: article,
                                    onRead: { openArticle(article) },
                                    onOpenURL: { webPage = IdentifiableURL(url: $0) },
                                    onShowStats: { statsArticle = article }
                                )
                            }
                            .listRowBackground(Theme.background)
                            .listRowSeparatorTint(Theme.border)
                            .trackingTopRow(id: article.id, space: Self.listSpace) { offset in
                                if let offset {
                                    visibleIDs.insert(article.id)
                                    rowOffsets[article.id] = offset
                                } else {
                                    visibleIDs.remove(article.id)
                                    rowOffsets.removeValue(forKey: article.id)
                                }
                                noteTopRow()
                            }
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
            .coordinateSpace(.named(Self.listSpace))
            .trackingTopInset { topInset = $0 }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .overlay {
                if ordered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .navigationTitle("Articles")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search \(articles.count) articles")
            .task {
                recompute()
                await restoreScroll(proxy)
            }
            .onChange(of: sort) { _, _ in recompute() }
            .onChange(of: appSettings.availableSorts()) { _, available in
                if !available.contains(sort) { sort = available.first ?? .newest }
                recompute()
            }
            .onChange(of: searchText) { _, text in
                session.listSearch = text
                recompute()
            }
            .onChange(of: engagement.sortContext) { _, _ in recompute() }
            .sheet(item: $webPage) { page in
                SafariView(url: page.url).ignoresSafeArea()
            }
            .sheet(item: $statsArticle) { article in
                ArticleStatsView(article: article)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingDownloads) {
                DownloadsView()
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
                    Button { showingDownloads = true } label: {
                        downloadsIcon
                    }
                    .accessibilityLabel("Downloads")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(appSettings.availableSorts()) { option in
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

    @Environment(OfflineLibrary.self) private var library

    /// Shows how much of the catalog is downloaded, and progress while a
    /// batch is running.
    @ViewBuilder
    private var downloadsIcon: some View {
        let downloaded = library.downloadedCount(of: articles)
        if library.isDownloadingAll {
            ProgressView(value: Double(downloaded), total: Double(max(articles.count, 1)))
                .progressViewStyle(.circular)
                .tint(Theme.accent)
        } else if downloaded == articles.count {
            Image(systemName: "arrow.down.circle.fill")
        } else {
            Image(systemName: "arrow.down.circle")
        }
    }

    @ViewBuilder
    private func offlineSwipeAction(for article: Article) -> some View {
        if library.isAvailableOffline(article) {
            Button("Remove Download", systemImage: "trash", role: .destructive) { library.remove(article) }
        } else {
            Button("Download", systemImage: "arrow.down.circle") { library.download(article) }
                .tint(Theme.accent)
        }
    }

    private func recompute() {
        ordered = sort.sorted(articles.filter { $0.matches(search: searchText) }, context: engagement.sortContext)
    }

    /// Records the row at the top of the list, so it comes back to it. Opening
    /// an article takes every row off screen, which isn't a new position — the
    /// last row seen stays recorded.
    private func noteTopRow() {
        guard restoredScroll else { return }
        guard let top = topRowID.flatMap({ id in ordered.first { $0.id == id } })
            ?? ordered.first(where: { visibleIDs.contains($0.id) }) else { return }
        session.listTopPostID = top.postID
    }

    /// The row at the top of the visible area: the first one that isn't
    /// scrolled up under the navigation bar.
    private var topRowID: Article.ID? {
        let onScreen = rowOffsets.filter { $0.value >= topInset - 8 }
        return onScreen.min { $0.value < $1.value }?.key
            ?? rowOffsets.min { abs($0.value - topInset) < abs($1.value - topInset) }?.key
    }

    private func restoreScroll(_ proxy: ScrollViewProxy) async {
        defer { restoredScroll = true }
        guard !restoredScroll,
              let postID = session.listTopPostID,
              let article = ordered.first(where: { $0.postID == postID }) else { return }
        // The list finishes laying out after this runs, and reorders again as
        // engagement stats arrive — either of which drops it back at the top.
        // Keep putting the row back until it stays.
        for _ in 0..<6 {
            proxy.scrollTo(article.id, anchor: .top)
            try? await Task.sleep(for: .milliseconds(120))
            if topRowID == article.id { break }
        }
    }

    private var sections: [(title: String?, articles: [Article])] {
        let inProgress = inProgressArticles
        let started = Set(inProgress.map(\.id))
        // Articles in progress appear once, at the top: a row in two places
        // confuses both the eye and the list's own row identity.
        let articles = started.isEmpty ? ordered : ordered.filter { !started.contains($0.id) }
        var result: [(title: String?, articles: [Article])] = []
        if !inProgress.isEmpty { result.append((Self.inProgressTitle, inProgress)) }
        guard sort.groupsByYear else {
            if !articles.isEmpty { result.append((inProgress.isEmpty ? nil : "All Articles", articles)) }
            return result
        }
        for article in articles {
            let year = article.publishedDate.map { String(Calendar.current.component(.year, from: $0)) } ?? "Undated"
            if result.last?.title == year, result.last?.title != Self.inProgressTitle {
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
    @Environment(ReadingStateStore.self) private var reading
    @Environment(AppSettings.self) private var appSettings

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
                if appSettings.showReadingProgress {
                    ReadingProgressLine(progress: reading.progress(for: article.postID))
                }
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
        .environment(ReadingStateStore.shared)
        .preferredColorScheme(.dark)
}

/// How far through an article you are, for articles you've started.
struct ReadingProgressLine: View {
    let progress: Double?

    private static let barWidth: CGFloat = 54

    var body: some View {
        if let progress, progress > 0.02 {
            if progress >= 0.97 {
                Label("Finished", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(Theme.accent)
            } else {
                HStack(spacing: 6) {
                    Capsule()
                        .fill(Theme.border)
                        .frame(width: Self.barWidth, height: 3)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Theme.accent)
                                .frame(width: Self.barWidth * progress, height: 3)
                        }
                    Text("\(Int((progress * 100).rounded()))% read")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(Theme.accent)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Int((progress * 100).rounded())) percent read")
            }
        }
    }
}

private extension View {
    /// Reports a row's distance from the top of the list as it scrolls, and nil
    /// when the row goes away. Falls back to appearance alone before iOS 18,
    /// where a row's position can't be observed without it moving.
    func trackingTopRow(id: Article.ID, space: String, onChange: @escaping (CGFloat?) -> Void) -> some View {
        onAppear { onChange(0) }
            .onDisappear { onChange(nil) }
            .modifier(RowOffsetReporter(space: space, onChange: onChange))
    }
}

private struct RowOffsetReporter: ViewModifier {
    let space: String
    let onChange: (CGFloat?) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(space)).minY
            } action: { offset in
                onChange(offset)
            }
        } else {
            content
        }
    }
}

private extension View {
    /// Where the list's visible area starts, which is below the navigation bar.
    func trackingTopInset(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        modifier(TopInsetReporter(onChange: onChange))
    }
}

private struct TopInsetReporter: ViewModifier {
    let onChange: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentInsets.top
            } action: { _, inset in
                onChange(inset)
            }
        } else {
            content
        }
    }
}
