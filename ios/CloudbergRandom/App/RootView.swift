import SwiftUI

struct RootView: View {
    // One navigation path per tab, so each tab keeps its own place.
    @State private var randomPath: [Article] = []
    @State private var articlesPath: [Article] = []
    // Remembers the last tab; also settable at launch with `-rootTab articles`.
    @AppStorage("rootTab") private var selectedTab = "random"

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $randomPath) {
                RandomArticleView()
                    .readerDestination()
            }
            .environment(\.openArticle, OpenArticleAction { randomPath.append($0) })
            .tabItem { Label("Random", systemImage: "dice") }
            .tag("random")

            NavigationStack(path: $articlesPath) {
                ArticleListView()
                    .readerDestination()
            }
            .environment(\.openArticle, OpenArticleAction { articlesPath.append($0) })
            .tabItem { Label("Articles", systemImage: "list.bullet") }
            .tag("articles")
        }
        .tint(Theme.accent)
        .environment(OfflineLibrary.shared)
        .environment(EngagementStore.shared)
        .environment(ReadingStateStore.shared)
        #if DEBUG
        .task {
            // `-debugDownloadNewest N` downloads the newest N articles at launch,
            // for exercising the offline library in the simulator without taps.
            let count = UserDefaults.standard.integer(forKey: "debugDownloadNewest")
            if count > 0 { OfflineLibrary.shared.downloadAll(Array(ArticleStore.all.suffix(count))) }
            // `-debugOpenArticle <postID>` opens an article in the reader at launch.
            if let postID = UserDefaults.standard.string(forKey: "debugOpenArticle"),
               let article = ArticleStore.all.first(where: { $0.postID == postID }) {
                selectedTab == "random" ? randomPath.append(article) : articlesPath.append(article)
            }
        }
        #endif
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
