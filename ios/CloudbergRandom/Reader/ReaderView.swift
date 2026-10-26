import SwiftUI

struct ReaderView: View {
    let article: Article

    @Environment(\.scenePhase) private var scenePhase
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
    /// Continuous scroll progress, which updates far more often than the top
    /// paragraph changes.
    @State private var scrollProgress: Double?

    @State private var detector = JumpDetector()
    @State private var returnOffer: JumpDetector.Jump?
    /// The saved place to pick up from, until the reader has been moved there.
    @State private var resumeBlockID: String?
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settings.palette.background, for: .navigationBar, .bottomBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbar }
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
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            if let document { saveCurrentPosition(in: document) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the app counts as putting the article down.
            if phase != .active, let document { saveCurrentPosition(in: document) }
        }
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
        .onReaderScrollProgress { progress in
            scrollProgress = progress
        }
        .onChange(of: topBlockID) { _, blockID in
            positionChanged(to: blockID, in: document)
        }
        .overlay(alignment: .bottom) { positionOffers(document) }
        .task {
            // Pick up where you left off, once the scroll view is in place.
            guard let blockID = resumeBlockID else { return }
            await Task.yield()
            ignoreJumpsUntil = .now.addingTimeInterval(1.5)
            scrollProgress = document.progress(at: blockID)
            topBlockID = blockID
            resumeBlockID = nil
        }
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
            // Moving the scroll position binding (rather than a ScrollViewReader
            // proxy) keeps the percentage and jump detection in step with the
            // jump instead of waiting for the scroll to settle.
            if scrollProgress == nil { scrollProgress = document.progress(at: target) }
            withAnimation { topBlockID = target }
            scrollTarget = nil
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
            if let percent = readPercentage {
                Text("\(percent)%")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(settings.palette.secondaryText)
                    // Follows the scroll directly; any transition reads as flicker.
                    .contentTransition(.identity)
                    .transaction { $0.animation = nil }
                    .accessibilityLabel("\(percent) percent read")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingSettings = true } label: {
                Image(systemName: "textformat.size")
            }
            .accessibilityLabel("Reading settings")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ArticleActionsMenu(article: article, onOpenURL: open)
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
                resumeBlockID = blockID
            }
            #if DEBUG
            // `-debugJumpToProgress 42` jumps as resuming would, for checking
            // that the percentage follows.
            let jumpPercent = UserDefaults.standard.integer(forKey: "debugJumpToProgress")
            if jumpPercent > 0 {
                // After the scroll view exists, so the jump isn't missed.
                Task {
                    try? await Task.sleep(for: .milliseconds(800))
                    scrollTarget = document.blockID(atProgress: Double(jumpPercent) / 100)
                }
            }
            #endif
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
                    move(to: returnOffer.fromBlockID, in: document)
                } onDismiss: {
                    self.returnOffer = nil
                    returnOfferIsSticky = false
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(duration: 0.35), value: returnOffer)
    }

    /// Percentage read, from the live scroll position when it's known.
    private var readPercentage: Int? {
        guard let progress = scrollProgress ?? document.flatMap({ document in
            topBlockID.map { document.progress(at: $0) }
        }) else { return nil }
        return Int((progress * 100).rounded())
    }

    private func positionChanged(to blockID: String?, in document: ReaderDocument) {
        guard let blockID else { return }
        let progress = scrollProgress ?? document.progress(at: blockID)
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
    }

    /// While reading, only settled positions are saved, so an accidental jump
    /// doesn't quietly become your saved place.
    private func saveSettledPosition(in document: ReaderDocument) {
        guard let settled = detector.settled else { return }
        savePosition(blockID: settled.blockID, progress: settled.progress)
    }

    /// Closing the article (or leaving the app) saves exactly where the view
    /// is, even if you scrolled there a moment ago.
    private func saveCurrentPosition(in document: ReaderDocument) {
        guard let blockID = topBlockID ?? detector.settled?.blockID else { return }
        savePosition(blockID: blockID, progress: scrollProgress ?? document.progress(at: blockID))
    }

    private func savePosition(blockID: String, progress: Double) {
        var state = ReadingStateStore.shared.state(for: article.postID)
        guard state.blockID != blockID else { return }
        // Don't overwrite a saved position with the top of the article before
        // the reader has been moved back to it.
        if resumeBlockID != nil { return }
        state.blockID = blockID
        state.progress = progress
        state.updatedAt = .now
        ReadingStateStore.shared.save(state, for: article.postID)
    }

    private func move(to blockID: String, in document: ReaderDocument) {
        ignoreJumpsUntil = .now.addingTimeInterval(1.5)
        withAnimation { returnOffer = nil }
        returnOfferIsSticky = false
        scrollTarget = blockID
    }

    private func open(_ url: URL) {
        webPage = IdentifiableURL(url: url)
    }
}
