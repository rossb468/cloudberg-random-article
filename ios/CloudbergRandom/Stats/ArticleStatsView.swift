import SwiftUI

/// Compact engagement numbers for list rows.
struct ArticleStatsLine: View {
    let stats: ArticleStats

    var body: some View {
        HStack(spacing: 10) {
            if let claps = stats.claps {
                Label(claps.formatted(.number.notation(.compactName)), systemImage: "hands.clap")
                    .accessibilityLabel("\(claps) claps")
            }
            if let score = stats.redditScore {
                Label(score.formatted(.number.notation(.compactName)), systemImage: "arrow.up")
                    .accessibilityLabel("\(score) Reddit upvotes")
            }
            if let discussion = stats.discussionCount {
                Label(discussion.formatted(.number.notation(.compactName)), systemImage: "bubble.left")
                    .accessibilityLabel("\(discussion) comments and responses")
            }
        }
        .labelStyle(CompactStatLabelStyle())
        .font(.caption2.monospacedDigit())
        .foregroundColor(Theme.textDim)
    }
}

private struct CompactStatLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// Full engagement breakdown for one article, with its rank in the archive.
struct ArticleStatsView: View {
    let article: Article

    @Environment(\.dismiss) private var dismiss
    @Environment(EngagementStore.self) private var store
    @State private var webPage: IdentifiableURL?

    var body: some View {
        let stats = store.stats(for: article)
        let ranking = store.ranking
        NavigationStack {
            List {
                Section {
                    Text(article.title)
                        .font(.headline)
                    if let rank = ranking.overallRank(of: article.postID) {
                        LabeledContent("Overall engagement", value: "#\(rank) of \(ranking.scores.count)")
                    }
                }

                Section {
                    stat("Claps", stats.claps, rank: ranking.rank(of: article.postID, by: .claps))
                    stat("Responses", stats.mediumResponses)
                    if let url = article.webURL {
                        Button("Open on Medium", systemImage: "safari") { webPage = IdentifiableURL(url: url) }
                    }
                } header: {
                    Text("Medium")
                } footer: {
                    if let updated = stats.mediumUpdatedAt {
                        Text("Updated \(updated.formatted(.relative(presentation: .named))).")
                    } else {
                        Text("From the app's catalog snapshot. Use Update Medium Stats in the Articles sort menu for current numbers.")
                    }
                }

                Section {
                    let discussions = RedditIndex.discussions(for: article)
                    if discussions.isEmpty {
                        Text("No r/CatastrophicFailure post found for this article.")
                            .foregroundStyle(.secondary)
                    } else {
                        stat("Upvotes", stats.redditScore, rank: ranking.rank(of: article.postID, by: .redditScore))
                        if let ratio = stats.redditUpvoteRatio {
                            LabeledContent("Upvoted", value: ratio.formatted(.percent.precision(.fractionLength(0))))
                        }
                        stat("Comments", stats.redditComments)
                        ForEach(discussions) { discussion in
                            if let url = discussion.url {
                                Button {
                                    webPage = IdentifiableURL(url: url)
                                } label: {
                                    Label(discussions.count == 1 ? "Open Discussion" : "Posted \(discussion.createdDate.formatted(date: .abbreviated, time: .omitted))",
                                          systemImage: "bubble.left.and.bubble.right")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Reddit")
                } footer: {
                    Text("Reddit numbers come from the Arctic Shift archive, which records each post about a day and a half after it's posted.")
                }

                Section {
                    stat("Comments and responses", stats.discussionCount, rank: ranking.rank(of: article.postID, by: .discussion))
                } header: {
                    Text("Discussion")
                }
            }
            .navigationTitle("Engagement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $webPage) { page in
                SafariView(url: page.url).ignoresSafeArea()
            }
        }
        .tint(Theme.accent)
    }

    @ViewBuilder
    private func stat(_ title: String, _ value: Int?, rank: Int? = nil) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(value.map { $0.formatted() } ?? "—")
                    .monospacedDigit()
                if let rank {
                    Text("#\(rank)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}
