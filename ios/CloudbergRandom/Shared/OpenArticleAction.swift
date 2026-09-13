import SwiftUI

/// How the app opens an article. Screens call `openArticle(article)` and
/// `RootView` decides what that means (web view, reader, ...), so features that
/// list articles don't need to know about features that display them.
struct OpenArticleAction {
    private let handler: (Article) -> Void

    init(_ handler: @escaping (Article) -> Void) {
        self.handler = handler
    }

    func callAsFunction(_ article: Article) {
        handler(article)
    }
}

private struct OpenArticleActionKey: EnvironmentKey {
    static let defaultValue = OpenArticleAction { _ in }
}

extension EnvironmentValues {
    var openArticle: OpenArticleAction {
        get { self[OpenArticleActionKey.self] }
        set { self[OpenArticleActionKey.self] = newValue }
    }
}
