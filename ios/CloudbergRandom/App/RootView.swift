import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let session = SessionState.shared

    // One navigation path per tab, so each tab keeps its own place.
    @State private var randomPath: [Article] = []
    @State private var articlesPath: [Article] = []
    @State private var selectedTab = SessionState.shared.tab

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $randomPath) {
                RandomArticleView()
                    .readerDestination()
            }
            .environment(\.openArticle, OpenArticleAction { randomPath.append($0) })
            .tabItem { Label("Random", systemImage: "dice") }
            .tag(SessionState.Tab.random)

            NavigationStack(path: $articlesPath) {
                ArticleListView()
                    .readerDestination()
            }
            .environment(\.openArticle, OpenArticleAction { articlesPath.append($0) })
            .tabItem { Label("Articles", systemImage: "list.bullet") }
            .tag(SessionState.Tab.articles)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(SessionState.Tab.settings)
        }
        .tint(Theme.accent)
        .environment(OfflineLibrary.shared)
        .environment(EngagementStore.shared)
        .environment(ReadingStateStore.shared)
        .environment(AppSettings.shared)
        .task {
            CloudSync.shared.start(
                syncables: [AppSettings.shared, ReaderSettings.shared, SessionState.shared],
                reading: ReadingStateStore.shared,
                enabled: { AppSettings.shared.syncWithiCloud }
            )
            reopenLastArticles()
        }
        .onChange(of: selectedTab) { _, tab in session.tab = tab }
        .onChange(of: randomPath) { _, path in session.setOpenPostID(path.last?.postID, for: .random) }
        .onChange(of: articlesPath) { _, path in session.setOpenPostID(path.last?.postID, for: .articles) }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the app is the last chance to write state before it may
            // be terminated in the background.
            if phase != .active { session.flush() }
        }
        #if DEBUG
        .task {
            // `-debugDownloadNewest N` downloads the newest N articles at launch,
            // for exercising the offline library in the simulator without taps.
            let count = UserDefaults.standard.integer(forKey: "debugDownloadNewest")
            if count > 0 { OfflineLibrary.shared.downloadAll(Array(ArticleStore.all.suffix(count))) }
            // `-rootTab articles` picks the tab, `-debugOpenArticle <postID>`
            // opens an article in the reader, both at launch.
            if let tab = UserDefaults.standard.string(forKey: "rootTab").flatMap(SessionState.Tab.init) {
                selectedTab = tab
            }
            if let postID = UserDefaults.standard.string(forKey: "debugOpenArticle"),
               let article = ArticleStore.article(postID: postID) {
                selectedTab == .random ? randomPath.append(article) : articlesPath.append(article)
            }
        }
        #endif
    }

    /// Reopens whatever was on screen last time.
    private func reopenLastArticles() {
        guard AppSettings.shared.reopenLastArticle else { return }
        if let postID = session.openPostID(for: .random), let article = ArticleStore.article(postID: postID) {
            randomPath = [article]
        }
        if let postID = session.openPostID(for: .articles), let article = ArticleStore.article(postID: postID) {
            articlesPath = [article]
        }
    }
}

private extension View {
    /// Articles open by pushing onto the current tab's stack, so they can be
    /// swiped back like any other pushed screen.
    func readerDestination() -> some View {
        navigationDestination(for: Article.self) { article in
            ReaderView(article: article)
        }
    }
}
