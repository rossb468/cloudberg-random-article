import SwiftUI

/// The actions for one article, for long-press context menus and the reader's
/// menu. Share comes first: it's the one people reach for most.
struct ArticleActionsMenu: View {
    let article: Article
    /// Omitted when the article is already open.
    var onRead: (() -> Void)?
    var onOpenURL: (URL) -> Void

    @Environment(OfflineLibrary.self) private var library
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if let url = article.webURL {
            ShareLink(item: url, subject: Text(article.title))
        }
        if let onRead {
            Button("Read", systemImage: "book", action: onRead)
        }
        switch library.status(for: article) {
        case .notDownloaded, .failed:
            Button("Download", systemImage: "arrow.down.circle") { library.download(article) }
        case .textOnly:
            Button("Download Images", systemImage: "arrow.down.circle.dotted") { library.download(article) }
        case .complete, .queued, .downloading:
            EmptyView()
        }
        if !settings.hideSocial {
            RedditDiscussionMenuItems(article: article, open: onOpenURL)
        }
        if let url = article.webURL {
            Button("Open on Medium", systemImage: "safari") { onOpenURL(url) }
        }
        // Destructive, so it sits at the bottom away from everything else.
        if library.isAvailableOffline(article) {
            Button("Remove Download", systemImage: "trash", role: .destructive) { library.remove(article) }
        }
    }
}
