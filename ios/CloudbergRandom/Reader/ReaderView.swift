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
    @State private var galleryStart: ReaderDocument.Image?
    @State private var scrollTarget: String?

    // Reading position
    @State private var topBlockID: String?
    @State private var detector = JumpDetector()
    @State private var returnOffer: JumpDetector.Jump?
    @State private var resumeOffer: ReadingState?
    /// Moves we make on the reader's behalf (resume, go back) aren't jumps.
    @State private var ignoreJumpsUntil = Date.distantPast
    /// Set when the offer came from navigating (contents, bookmarks, stepping):
    /// it stays until used or dismissed so you can look something up and return.
    @State private var returnOfferIsSticky = false

    // Bookmarks & sections
    @State private var bookmarks: [Bookmark] = []
    @State private var showingNavigator = false
    @State private var showingMedia = false

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
        .onChange(of: bookmarks) { _, bookmarks in
            var state = ReadingStateStore.shared.state(for: article.postID)
            state.bookmarks = bookmarks
            ReadingStateStore.shared.save(state, for: article.postID)
        }
        .sheet(isPresented: $showingMedia) {
            if let document {
                MediaBrowserView(document: document) { blockID in
                    navigate(to: blockID, in: document)
                }
            }
        }
        .sheet(isPresented: $showingNavigator) {
            if let document {
                NavigatorView(document: document, currentBlockID: topBlockID, bookmarks: $bookmarks) { blockID in
                    navigate(to: blockID, in: document)
                }
                .presentationDetents([.medium, .large])
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn
            #if DEBUG
            showingSettings = UserDefaults.standard.bool(forKey: "debugShowReaderSettings")
            showingNavigator = UserDefaults.standard.string(forKey: "debugShowReaderPanel") == "contents"
            showingMedia = UserDefaults.standard.string(forKey: "debugShowReaderPanel") == "media"
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
        .fullScreenCover(item: $galleryStart) { start in
            if let document {
                ImageGalleryView(images: document.images, startingAt: start) { image in
                    navigate(to: image.blockID, in: document)
                }
            }
        }
        .sheet(item: $webPage) { page in
            SafariView(url: page.url).ignoresSafeArea()
        }
    }

    // MARK: - Content

    private func articleBody(_ document: ReaderDocument) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 24)
                ForEach(document.blocks) { block in
                    ReaderBlockView(block: block, settings: settings, onOpenURL: open) { metadata in
                        galleryStart = document.images.first { $0.blockID == block.id && $0.metadata.id == metadata.id }
                    }
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
        .scrollPosition(id: $topBlockID, anchor: .top)
        .onChange(of: topBlockID) { _, blockID in
            positionChanged(to: blockID, in: document)
        }
        .overlay(alignment: .bottom) { positionOffers(document) }
        .task {
            // Let positions settle while the reader isn't scrolling.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                detector.tick(at: .now)
                saveSettledPosition(in: document)
            }
        }
        .task(id: returnOffer) {
            guard returnOffer != nil, !returnOfferIsSticky else { return }
            try? await Task.sleep(for: .seconds(12))
            withAnimation { returnOffer = nil }
        }
        .onChange(of: scrollTarget) { _, target in
            guard let target else { return }
            withAnimation { proxy.scrollTo(target, anchor: .top) }
            scrollTarget = nil
        }
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
        ToolbarItemGroup(placement: .bottomBar) {
            if let document {
                let previous = document.previousStop(before: topBlockID, bookmarks: bookmarks)
                let next = document.nextStop(after: topBlockID, bookmarks: bookmarks)
                Button { showingNavigator = true } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("Contents and bookmarks")
                Spacer()
                Button { previous.map { navigate(to: $0.blockID, in: document) } } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(previous == nil)
                .accessibilityLabel("Previous section or bookmark")
                Button { toggleBookmark(in: document) } label: {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                }
                .sensoryFeedback(.selection, trigger: bookmarks.count)
                .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark this paragraph")
                Button { next.map { navigate(to: $0.blockID, in: document) } } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(next == nil)
                .accessibilityLabel("Next section or bookmark")
                Spacer()
                Button { showingMedia = true } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                }
                .disabled(document.images.isEmpty)
                .accessibilityLabel("Browse images")
            }
        }
        ToolbarItem(placement: .principal) {
            if let document, let topBlockID {
                Text("\(Int((document.progress(at: topBlockID) * 100).rounded()))%")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(settings.palette.secondaryText)
                    .accessibilityLabel("\(Int((document.progress(at: topBlockID) * 100).rounded())) percent read")
            }
        }
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
                RedditDiscussionMenuItems(article: article, open: open)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        do {
            let post = try await library.post(for: article)
            let document = ReaderDocument(post: post, title: article.title)
            self.document = document
            let saved = ReadingStateStore.shared.state(for: article.postID)
            bookmarks = saved.bookmarks
            if let blockID = saved.blockID, document.index(of: blockID) != nil, saved.progress > 0.02 {
                resumeOffer = saved
            }
            #if DEBUG
            // `-debugOpenImage N` opens the gallery at the Nth image.
            let imageNumber = UserDefaults.standard.integer(forKey: "debugOpenImage")
            if document.images.indices.contains(imageNumber - 1) {
                galleryStart = document.images[imageNumber - 1]
            }
            #endif
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Bookmarks & sections

    private var isBookmarked: Bool {
        guard let topBlockID else { return false }
        return bookmarks.contains { $0.blockID == topBlockID }
    }

    private func toggleBookmark(in document: ReaderDocument) {
        guard let blockID = topBlockID ?? document.blocks.first?.id else { return }
        if let index = bookmarks.firstIndex(where: { $0.blockID == blockID }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.append(Bookmark(blockID: blockID, excerpt: document.excerpt(at: blockID)))
        }
    }

    /// Moves to a section, bookmark or image, leaving a way back to where you
    /// were reading.
    private func navigate(to blockID: String, in document: ReaderDocument) {
        if returnOffer == nil, let origin = topBlockID, origin != blockID {
            withAnimation {
                returnOffer = JumpDetector.Jump(
                    fromBlockID: origin,
                    fromProgress: document.progress(at: origin),
                    toProgress: document.progress(at: blockID)
                )
            }
            returnOfferIsSticky = true
        }
        ignoreJumpsUntil = .now.addingTimeInterval(1.5)
        scrollTarget = blockID
    }

    // MARK: - Reading position

    @ViewBuilder
    private func positionOffers(_ document: ReaderDocument) -> some View {
        Group {
            if let returnOffer {
                ReturnPill(jump: returnOffer, palette: settings.palette) {
                    move(to: returnOffer.fromBlockID)
                } onDismiss: {
                    self.returnOffer = nil
                    returnOfferIsSticky = false
                }
            } else if let resumeOffer, let blockID = resumeOffer.blockID {
                ResumeBanner(progress: resumeOffer.progress, palette: settings.palette) {
                    move(to: blockID)
                } onDismiss: {
                    self.resumeOffer = nil
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(duration: 0.35), value: returnOffer)
        .animation(.spring(duration: 0.35), value: resumeOffer)
    }

    private func positionChanged(to blockID: String?, in document: ReaderDocument) {
        guard let blockID else { return }
        let progress = document.progress(at: blockID)
        let now = Date.now

        if now < ignoreJumpsUntil {
            // Start fresh from wherever we were moved to.
            detector = JumpDetector()
            _ = detector.update(blockID: blockID, progress: progress, at: now)
        } else if let jump = detector.update(blockID: blockID, progress: progress, at: now), !returnOfferIsSticky {
            withAnimation { returnOffer = jump }
        }

        if let offer = returnOffer, abs(progress - offer.fromProgress) < 0.02, now >= ignoreJumpsUntil {
            withAnimation { returnOffer = nil }
            returnOfferIsSticky = false
        }
        if resumeOffer != nil, progress > 0.1 {
            withAnimation { resumeOffer = nil }
        }
    }

    /// Only settled positions are saved, so an accidental jump right before
    /// closing the article doesn't lose your place.
    private func saveSettledPosition(in document: ReaderDocument) {
        guard let settled = detector.settled else { return }
        var state = ReadingStateStore.shared.state(for: article.postID)
        guard state.blockID != settled.blockID else { return }
        // Don't overwrite a saved position with the top of the article while the
        // resume offer is still up.
        if resumeOffer != nil && settled.progress < 0.02 { return }
        state.blockID = settled.blockID
        state.progress = settled.progress
        state.updatedAt = .now
        ReadingStateStore.shared.save(state, for: article.postID)
    }

    private func move(to blockID: String) {
        ignoreJumpsUntil = .now.addingTimeInterval(1.5)
        withAnimation {
            returnOffer = nil
            resumeOffer = nil
        }
        returnOfferIsSticky = false
        scrollTarget = blockID
    }

    private func open(_ url: URL) {
        webPage = IdentifiableURL(url: url)
    }
}
