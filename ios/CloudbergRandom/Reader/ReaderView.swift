import SwiftUI

struct ReaderView: View {
    let article: Article

    @Environment(\.dismiss) private var dismiss
    @Environment(OfflineLibrary.self) private var library
    private let settings = ReaderSettings.shared

    @State private var document: ReaderDocument?
    @State private var loadError: String?
    @State private var webPage: IdentifiableURL?
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if let document {
                    articleBody(document)
                } else if let loadError {
                    failure(loadError)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(settings.palette.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(settings.palette.background, for: .navigationBar, .bottomBar)
            .toolbar { toolbar }
        }
        .tint(settings.palette.accent)
        .preferredColorScheme(settings.palette.colorScheme)
        .task { await load() }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn
            #if DEBUG
            showingSettings = UserDefaults.standard.bool(forKey: "debugShowReaderSettings")
            #endif
        }
        .onChange(of: settings.keepScreenOn) { _, keepOn in
            UIApplication.shared.isIdleTimerDisabled = keepOn
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsView(settings: settings)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(item: $webPage) { page in
            SafariView(url: page.url).ignoresSafeArea()
        }
    }

    // MARK: - Content

    private func articleBody(_ document: ReaderDocument) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 24)
                ForEach(document.blocks) { block in
                    ReaderBlockView(block: block, settings: settings, onOpenURL: open)
                        .padding(.bottom, spacing(after: block))
                        .id(block.id)
                }
                footer
            }
            .scrollTargetLayout()
            .frame(maxWidth: settings.maxLineWidth)
            .padding(.horizontal, settings.margin)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(article.title)
                .font(Font(settings.typeface.font(size: CGFloat(settings.fontSize) * 1.55, bold: true) as CTFont))
                .foregroundStyle(settings.palette.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("Admiral Cloudberg")
                if let date = article.publishedDateText { Text("·"); Text(date) }
                if let time = article.readingTimeText { Text("·"); Text(time) }
            }
            .font(.footnote)
            .foregroundStyle(settings.palette.secondaryText)
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Text("◊ ◊ ◊")
                .foregroundStyle(settings.palette.secondaryText)
            Button("Read on Medium") { article.webURL.map(open) }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func spacing(after block: ReaderDocument.Block) -> CGFloat {
        let base = CGFloat(settings.fontSize)
        switch block.content {
        case .text(.body, _, _) where settings.indentParagraphs:
            return base * 0.25
        case .text(.body, _, _), .text(.bullet, _, _), .text(.numbered, _, _):
            return base * CGFloat(settings.paragraphSpacing)
        default:
            return base * CGFloat(max(settings.paragraphSpacing, 0.8)) * 1.3
        }
    }

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load the article", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                loadError = nil
                Task { await load() }
            }
            .buttonStyle(.borderedProminent)
            Button("Open on Medium") { article.webURL.map(open) }
        }
        .foregroundStyle(settings.palette.text)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Close")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingSettings = true } label: {
                Image(systemName: "textformat.size")
            }
            .accessibilityLabel("Reading settings")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let url = article.webURL {
                    Button("Open on Medium", systemImage: "safari") { open(url) }
                    ShareLink(item: url, subject: Text(article.title))
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        do {
            let post = try await library.post(for: article)
            document = ReaderDocument(post: post, title: article.title)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func open(_ url: URL) {
        webPage = IdentifiableURL(url: url)
    }
}
