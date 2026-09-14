import Foundation
import Observation

/// Current engagement stats for every article: the bundled Medium and Reddit
/// snapshots, updated with Medium numbers whenever the app reads an article
/// page, or on request for the whole catalog.
@MainActor
@Observable
final class EngagementStore {
    static let shared = EngagementStore()

    private(set) var ranking: EngagementRanking
    private(set) var isRefreshing = false
    private(set) var refreshProgress: (done: Int, total: Int) = (0, 0)
    private(set) var lastRefreshFailures = 0

    private var mediumOverrides: [String: MediumEngagement]
    private var stats: [String: ArticleStats] = [:]
    private let articles: [Article]
    private let file: URL
    private var refreshTask: Task<Void, Never>?

    init(articles: [Article] = ArticleStore.all, file: URL? = nil) {
        self.articles = articles
        self.file = file ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MediumEngagement.json")
        mediumOverrides = (try? Data(contentsOf: self.file))
            .flatMap { try? JSONDecoder().decode([String: MediumEngagement].self, from: $0) } ?? [:]
        ranking = EngagementRanking(stats: [:])
        rebuild()
    }

    var sortContext: ArticleSort.Context {
        ArticleSort.Context(stats: stats, ranking: ranking)
    }

    func stats(for article: Article) -> ArticleStats {
        stats[article.postID] ?? ArticleStats.from(article: article, discussions: [], mediumOverride: nil)
    }

    /// Records Medium's numbers from a freshly fetched page.
    func record(claps: Int?, responses: Int?, for postID: String) {
        guard let claps, let responses else { return }
        mediumOverrides[postID] = MediumEngagement(claps: claps, responses: responses, updatedAt: .now)
        rebuild()
        save()
    }

    /// Re-reads every article page from Medium for current claps and responses.
    func refreshMediumStats(client: MediumClient = MediumClient()) {
        guard refreshTask == nil else { return }
        isRefreshing = true
        lastRefreshFailures = 0
        refreshProgress = (0, articles.count)
        refreshTask = Task {
            await withTaskGroup(of: (String, MediumClient.Engagement?).self) { group in
                var queue = articles.makeIterator()
                func enqueue() {
                    guard let article = queue.next() else { return }
                    group.addTask { (article.postID, try? await client.fetchEngagement(for: article)) }
                }
                for _ in 0..<3 { enqueue() }
                while let (postID, engagement) = await group.next() {
                    refreshProgress.done += 1
                    if let engagement {
                        mediumOverrides[postID] = MediumEngagement(claps: engagement.claps, responses: engagement.responses, updatedAt: .now)
                    } else {
                        lastRefreshFailures += 1
                    }
                    if !Task.isCancelled { enqueue() }
                }
            }
            rebuild()
            save()
            isRefreshing = false
            refreshTask = nil
        }
    }

    func cancelRefresh() {
        refreshTask?.cancel()
    }

    private func rebuild() {
        stats = Dictionary(uniqueKeysWithValues: articles.map { article in
            (article.postID, ArticleStats.from(
                article: article,
                discussions: RedditIndex.discussions(for: article),
                mediumOverride: mediumOverrides[article.postID]
            ))
        })
        ranking = EngagementRanking(stats: stats)
    }

    private func save() {
        try? JSONEncoder().encode(mediumOverrides).write(to: file, options: .atomic)
    }
}
