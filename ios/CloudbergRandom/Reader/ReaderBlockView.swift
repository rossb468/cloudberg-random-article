import SwiftUI

struct ReaderBlockView: View {
    let block: ReaderDocument.Block
    let settings: ReaderSettings
    var onOpenURL: (URL) -> Void
    var onOpenImage: (MediumImageMetadata) -> Void = { _ in }

    var body: some View {
        switch block.content {
        case .text(.blockquote, let text, let markups):
            HStack(alignment: .top, spacing: 14) {
                Rectangle()
                    .fill(settings.palette.accent.opacity(0.7))
                    .frame(width: 3)
                richText(text, markups: markups, style: .blockquote)
            }
        case .text(.pullQuote, let text, let markups):
            richText(text, markups: markups, style: .pullQuote)
                .padding(.vertical, 12)
        case .text(let style, let text, let markups):
            richText(text, markups: markups, style: style)
                .padding(.top, style == .heading || style == .subheading ? CGFloat(settings.fontSize) * 0.6 : 0)
        case .figure(let images, let caption, let markups, let layout):
            figure(images, caption: caption, markups: markups, layout: layout)
        case .sectionBreak:
            Text("◊ ◊ ◊")
                .font(.body)
                .foregroundStyle(settings.palette.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        case .embed(let embed, let caption):
            embedCard(embed, caption: caption)
        case .link(let url, let title):
            linkCard(url: url, title: title)
        }
    }

    private func richText(_ text: String, markups: [MediumMarkup], style: ReaderDocument.TextStyle) -> some View {
        ReaderText(
            attributedText: ReaderTypesetter.text(text, markups: markups, style: style, settings: settings),
            linkColor: settings.palette.accent,
            onOpenLink: onOpenURL
        )
    }

    @ViewBuilder
    private func figure(_ images: [MediumImageMetadata], caption: String, markups: [MediumMarkup],
                        layout: ReaderDocument.FigureLayout) -> some View {
        VStack(spacing: 8) {
            if layout == .row {
                HStack(spacing: 4) {
                    ForEach(images, id: \.id) { image in
                        tappableImage(image)
                    }
                }
            } else if let image = images.first {
                tappableImage(image)
                    .frame(maxWidth: .infinity)
            }
            if !caption.isEmpty {
                ReaderText(
                    attributedText: ReaderTypesetter.caption(caption, markups: markups, settings: settings),
                    linkColor: settings.palette.accent,
                    onOpenLink: onOpenURL
                )
                .padding(.horizontal, 8)
            }
        }
        // Wide figures bleed into the margins.
        .padding(.horizontal, layout == .wide ? -CGFloat(settings.margin) * 0.6 : 0)
    }

    private func tappableImage(_ image: MediumImageMetadata) -> some View {
        ArticleImage(id: image.id, aspectRatio: image.aspectRatio)
            .contentShape(Rectangle())
            .onTapGesture { onOpenImage(image) }
            .contextMenu {
                Button("View Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") { onOpenImage(image) }
                Button("Save to Photos", systemImage: "square.and.arrow.down") {
                    Task { _ = await ImageActions.save(id: image.id) }
                }
                Button("Copy", systemImage: "doc.on.doc") {
                    Task { await ImageActions.copy(id: image.id) }
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(image.alt ?? "Image")
            .accessibilityHint("Opens the image full screen")
    }

    private func embedCard(_ embed: MediumEmbed, caption: String) -> some View {
        Button {
            URL(string: embed.url).map(onOpenURL)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    AsyncImage(url: embed.thumbnailURL.flatMap(URL.init(string:))) { phase in
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            settings.palette.secondaryText.opacity(0.15)
                        }
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipped()
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 54))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(caption.isEmpty ? (embed.title ?? "Watch video") : caption)
                    .font(.footnote)
                    .foregroundStyle(settings.palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play video: \(embed.title ?? caption)")
    }

    private func linkCard(url: String, title: String) -> some View {
        Button {
            URL(string: url).map(onOpenURL)
        } label: {
            HStack {
                Image(systemName: "link")
                Text(title)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .font(.subheadline)
            .foregroundStyle(settings.palette.text)
            .padding(12)
            .background(settings.palette.secondaryText.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
