import SwiftUI

struct RandomArticleView: View {
    @Environment(\.openArticle) private var openArticle

    private let articles = ArticleStore.all

    @State private var currentIndex: Int = -1
    @State private var lastIndex: Int = -1
    @State private var safariTarget: IdentifiableURL?
    /// Loaded covers, so a new card arrives with its image already in place and
    /// slides in as one piece. Holds the outgoing card's cover too, so it keeps
    /// its image while it slides away.
    @State private var covers: [Article.ID: UIImage] = [:]
    @State private var pendingPick: Task<Void, Never>?
    private let session = SessionState.shared
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header

                    if let article = currentArticle {
                        VStack(spacing: 16) {
                            Button {
                                openArticle(article)
                            } label: {
                                card(for: article)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens the article")

                            Text("Article \(currentIndex + 1) of \(articles.count) in the archive")
                                .font(.footnote)
                                .foregroundColor(Theme.textDim)

                            newArticleButton

                            if !appSettings.hideSocial {
                                RedditDiscussionLink(article: article) { safariTarget = IdentifiableURL(url: $0) }
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .id(article.id)
                    } else {
                        Text("No article data found")
                            .foregroundColor(Theme.text)
                            .padding(.top, 40)
                    }

                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .refreshable { await pickRandomArticle() }
        }
        .onAppear {
            guard currentIndex == -1 else { return }
            // The card that was showing last time, rather than a fresh roll on
            // every launch.
            if let postID = session.randomPostID,
               let index = articles.firstIndex(where: { $0.postID == postID }) {
                currentIndex = index
                lastIndex = index
            } else {
                showRandomArticle()
            }
        }
        .sheet(item: $safariTarget) { target in
            SafariView(url: target.url)
        }
    }

    private var currentArticle: Article? {
        guard articles.indices.contains(currentIndex) else { return nil }
        return articles[currentIndex]
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("✈️ Random Admiral Cloudberg")
                .font(.title2.bold())
                .foregroundColor(Theme.text)
            Text("A random deep-dive from Admiral Cloudberg on Medium")
                .font(.subheadline)
                .foregroundColor(Theme.textDim)
                .multilineTextAlignment(.center)
                .onTapGesture {
                    if let url = URL(string: "https://admiralcloudberg.medium.com") {
                        safariTarget = IdentifiableURL(url: url)
                    }
                }
        }
        .padding(.bottom, 4)
    }

    private func card(for article: Article) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cover(for: article)

            VStack(alignment: .leading, spacing: 12) {
                metaRow(for: article)

                Text(article.title)
                    .font(.title3.bold())
                    .foregroundColor(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = article.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

            }
            .padding(20)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        .contextMenu {
            ArticleActionsMenu(
                article: article,
                onRead: { openArticle(article) },
                onOpenURL: { safariTarget = IdentifiableURL(url: $0) }
            )
        }
    }

    private func cover(for article: Article) -> some View {
        ZStack {
            if let image = covers[article.id] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .clipped()
        .task(id: article.id) {
            // Usually already loaded before the card was shown; this covers the
            // first card and covers that took too long to wait for.
            guard covers[article.id] == nil, let image = await coverImage(for: article) else { return }
            withAnimation(.easeOut(duration: 0.2)) { covers[article.id] = image }
        }
    }

    private func coverImage(for article: Article) async -> UIImage? {
        guard let id = article.image, !id.isEmpty else { return nil }
        return try? await ImageLoader.shared.load(id: id).image
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color(red: 0x1e / 255, green: 0x23 / 255, blue: 0x30 / 255))
            .overlay(Text("✈️").font(.system(size: 40)))
    }

    private func metaRow(for article: Article) -> some View {
        HStack(spacing: 10) {
            if let date = article.publishedDateText {
                Text(date.uppercased())
            }
            if let readingTime = article.readingTimeText {
                Text(readingTime.uppercased())
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundColor(Theme.textDim)
        .tracking(0.6)
    }

    private var newArticleButton: some View {
        Button(action: showRandomArticle) {
            Label("New random article", systemImage: "dice")
                .font(.subheadline.bold())
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Theme.accent)
                .foregroundColor(Theme.accentText)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 2) {
            Text("All writing belongs to Admiral Cloudberg.")
        }
        .font(.caption)
        .foregroundColor(Theme.textDim)
        .multilineTextAlignment(.center)
        .padding(.top, 12)
    }

    private func showRandomArticle() {
        pendingPick?.cancel()
        pendingPick = Task { await pickRandomArticle() }
    }

    private func pickRandomArticle() async {
        guard !articles.isEmpty else { return }
        var index: Int
        repeat {
            index = Int.random(in: 0..<articles.count)
        } while articles.count > 1 && appSettings.avoidRecentRandom && index == lastIndex

        lastIndex = index
        let article = articles[index]

        // Load the cover first, but don't hold up the card for a slow network.
        let image = await withTaskGroup(of: UIImage?.self) { group in
            group.addTask { await coverImage(for: article) }
            group.addTask {
                try? await Task.sleep(for: .seconds(1.5))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard !Task.isCancelled else { return }
        // Only the outgoing and incoming cards need their covers.
        let outgoing = currentArticle?.id
        covers = covers.filter { $0.key == outgoing }
        if let image { covers[article.id] = image }
        session.randomPostID = article.postID
        withAnimation(.easeOut(duration: 0.3)) {
            currentIndex = index
        }
    }
}

struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

#Preview {
    RandomArticleView()
}
