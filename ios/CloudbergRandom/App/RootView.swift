import SwiftUI

struct RootView: View {
    @State private var openedArticle: Article?

    var body: some View {
        RandomArticleView()
            .environment(\.openArticle, OpenArticleAction { openedArticle = $0 })
            .sheet(item: $openedArticle) { article in
                if let url = article.webURL {
                    SafariView(url: url)
                        .ignoresSafeArea()
                }
            }
    }
}
