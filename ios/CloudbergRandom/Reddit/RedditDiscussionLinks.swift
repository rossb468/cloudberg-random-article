import SwiftUI

/// Menu items linking an article's Reddit discussions. Most articles have one
/// post; a few were posted more than once.
struct RedditDiscussionMenuItems: View {
    let article: Article
    var open: (URL) -> Void

    var body: some View {
        let discussions = RedditIndex.discussions(for: article)
        if discussions.count == 1, let url = discussions[0].url {
            Button("Discussion on \(RedditIndex.subreddit)", systemImage: "bubble.left.and.bubble.right") { open(url) }
        } else if discussions.count > 1 {
            Menu("Discussions on \(RedditIndex.subreddit)", systemImage: "bubble.left.and.bubble.right") {
                ForEach(discussions) { discussion in
                    if let url = discussion.url {
                        Button(discussion.createdDate.formatted(date: .abbreviated, time: .omitted)) { open(url) }
                    }
                }
            }
        }
    }
}

/// Inline link to an article's main Reddit discussion, for cards.
struct RedditDiscussionLink: View {
    let article: Article
    var open: (URL) -> Void

    var body: some View {
        if let discussion = RedditIndex.discussions(for: article).first, let url = discussion.url {
            Button {
                open(url)
            } label: {
                Label("Discuss on \(RedditIndex.subreddit)", systemImage: "bubble.left.and.bubble.right")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundColor(Theme.accent)
        }
    }
}
