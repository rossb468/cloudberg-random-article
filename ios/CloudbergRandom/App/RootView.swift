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
        }
        .tint(Theme.accent)
        .environment(\.openArticle, OpenArticleAction { openedArticle = $0 })
        .sheet(item: $openedArticle) { article in
            if let url = article.webURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }
}
