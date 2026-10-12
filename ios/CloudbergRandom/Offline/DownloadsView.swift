import SwiftUI

/// Download management for the whole catalog, opened from the Articles tab.
struct DownloadsView: View {
    @Environment(\.openArticle) private var openArticle
    @Environment(\.dismiss) private var dismiss
    @Environment(OfflineLibrary.self) private var library
    @State private var confirmingRemoveAll = false

    private let articles = ArticleStore.all

    var body: some View {
        @Bindable var library = library
        NavigationStack {
            List {
                Section {
                    summary
                    Toggle("Include images", isOn: $library.includeImages)
                        .tint(Theme.accent)
                } footer: {
                    Text("Images take up nearly all of the space — about 3 GB for the whole archive. Without them downloads are a small fraction of that, and articles are still fully readable offline, with image placeholders.")
                }
                .listRowBackground(Theme.card)

                if !inProgress.isEmpty {
                    Section("In progress") {
                        ForEach(inProgress) { article in
                            OfflineArticleRow(article: article)
                        }
                    }
                    .listRowBackground(Theme.card)
                }

                if !downloaded.isEmpty {
                    Section("Available offline") {
                        ForEach(downloaded) { article in
                            Button {
                                dismiss()
                                openArticle(article)
                            } label: {
                                OfflineArticleRow(article: article)
                            }
                            .swipeActions {
                                Button("Remove", role: .destructive) { library.remove(article) }
                            }
                        }
                    }
                    .listRowBackground(Theme.card)

                    Section {
                        Button("Remove All Downloads", role: .destructive) {
                            confirmingRemoveAll = true
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Remove all downloaded articles?", isPresented: $confirmingRemoveAll, titleVisibility: .visible) {
                Button("Remove All", role: .destructive) { library.removeAll() }
            } message: {
                Text("This frees \(storageText). Your reading positions and bookmarks are kept.")
            }
        }
    }

    private var summary: some View {
        let complete = library.downloadedCount(of: articles)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(complete) of \(articles.count)")
                    .font(.title2.bold().monospacedDigit())
                Text("articles downloaded")
                    .foregroundColor(Theme.textDim)
                Spacer()
                Text(storageText)
                    .font(.footnote.monospacedDigit())
                    .foregroundColor(Theme.textDim)
            }
            ProgressView(value: Double(complete), total: Double(max(articles.count, 1)))
                .tint(Theme.accent)

            if library.isDownloadingAll {
                Button {
                    library.stopDownloadingAll()
                } label: {
                    Label("Stop Downloading", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
                Text("Keep Cloudberg open while downloading — the screen won't lock. You can close this sheet; downloads keep going.")
                    .font(.caption)
                    .foregroundColor(Theme.textDim)
            } else if complete < articles.count {
                Button {
                    library.downloadAll(articles)
                } label: {
                    Label("Download All", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .foregroundColor(Theme.accentText)
            }
        }
        .padding(.vertical, 6)
    }

    private var storageText: String {
        ByteCountFormatter.string(fromByteCount: library.storageBytes, countStyle: .file)
    }

    private var inProgress: [Article] {
        articles.filter {
            switch library.status(for: $0) {
            case .queued, .downloading, .failed: true
            default: false
            }
        }
    }

    private var downloaded: [Article] {
        articles.filter { library.isAvailableOffline($0) }.reversed()
    }
}

struct OfflineArticleRow: View {
    let article: Article

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(article.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                if let date = article.publishedDateText {
                    Text(date).font(.caption).foregroundColor(Theme.textDim)
                }
            }
            Spacer()
            OfflineStatusIcon(article: article)
        }
    }
}

/// Download state for one article; tap to download, retry, or (when idle) nothing.
struct OfflineStatusIcon: View {
    @Environment(OfflineLibrary.self) private var library
    let article: Article

    var body: some View {
        switch library.status(for: article) {
        case .notDownloaded:
            Button { library.download(article) } label: {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.borderless)
            .foregroundColor(Theme.textDim)
            .accessibilityLabel("Download for offline reading")
        case .queued:
            Image(systemName: "clock")
                .foregroundColor(Theme.textDim)
                .accessibilityLabel("Queued")
        case .downloading(let progress):
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .tint(Theme.accent)
                .frame(width: 22, height: 22)
        case .failed(let message):
            Button { library.download(article) } label: {
                Image(systemName: "exclamationmark.arrow.circlepath")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
            .accessibilityLabel("Download failed: \(message). Retry")
        case .textOnly:
            Button { library.download(article) } label: {
                Image(systemName: "arrow.down.circle.dotted")
            }
            .buttonStyle(.borderless)
            .foregroundColor(Theme.accent)
            .accessibilityLabel("Text saved. Download images")
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Theme.accent)
                .accessibilityLabel("Available offline")
        }
    }
}
