import SwiftUI

struct RootView: View {
    @State private var openedArticle: Article?
    // Remembers the last tab; also settable at launch with `-rootTab articles`.
    @AppStorage("rootTab") private var selectedTab = "random"

    var body: some View {
        TabView(selection: $selectedTab) {
            RandomArticleView()
                .tabItem { Label("Random", systemImage: "dice") }
                .tag("random")
            ArticleListView()
                .tabItem { Label("Articles", systemImage: "list.bullet") }
                .tag("articles")
            LibraryView()
                .tabItem { Label("Library", systemImage: "arrow.down.circle") }
                .tag("library")
        }
        .tint(Theme.accent)
        .environment(OfflineLibrary.shared)
        .environment(EngagementStore.shared)
        .environment(\.openArticle, OpenArticleAction { openedArticle = $0 })
        #if DEBUG
        .task {
            // `-debugDownloadNewest N` downloads the newest N articles at launch,
            // for exercising the offline library in the simulator without taps.
            let count = UserDefaults.standard.integer(forKey: "debugDownloadNewest")
            if count > 0 { OfflineLibrary.shared.downloadAll(Array(ArticleStore.all.suffix(count))) }
            // `-debugOpenArticle <postID>` opens an article in the reader at launch.
            if let postID = UserDefaults.standard.string(forKey: "debugOpenArticle") {
                openedArticle = ArticleStore.all.first { $0.postID == postID }
            }
        }
        #endif
        .fullScreenCover(item: $openedArticle) { article in
            ReaderView(article: article)
                .environment(OfflineLibrary.shared)
                .environment(EngagementStore.shared)
        }
    }
}
