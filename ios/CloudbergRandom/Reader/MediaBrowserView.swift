import SwiftUI

/// All of an article's images and their captions, grouped by section, apart
/// from the text.
struct MediaBrowserView: View {
    let document: ReaderDocument
    var onShowInArticle: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("mediaBrowser.grid") private var showsGrid = true
    @State private var galleryStart: ReaderDocument.Image?

    private struct ImageSection: Identifiable {
        let landmark: ReaderDocument.Landmark?
        var images: [ReaderDocument.Image]
        var id: String { images.first?.id ?? "" }
    }

    private var sections: [ImageSection] {
        var result: [ImageSection] = []
        for image in document.images {
            let landmark = document.landmark(containing: image.blockID)
            if result.last?.landmark == landmark {
                result[result.count - 1].images.append(image)
            } else {
                result.append(ImageSection(landmark: landmark, images: [image]))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: .sectionHeaders) {
                    ForEach(sections) { section in
                        Section {
                            if showsGrid {
                                grid(section.images)
                            } else {
                                list(section.images)
                            }
                        } header: {
                            header(section.landmark)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .overlay {
                if document.images.isEmpty {
                    ContentUnavailableView("No Images", systemImage: "photo.on.rectangle")
                }
            }
            .navigationTitle("\(document.images.count) Images")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Layout", selection: $showsGrid) {
                        Image(systemName: "square.grid.3x3").tag(true).accessibilityLabel("Grid")
                        Image(systemName: "list.bullet.below.rectangle").tag(false).accessibilityLabel("List with captions")
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
        .fullScreenCover(item: $galleryStart) { start in
            ImageGalleryView(images: document.images, startingAt: start) { image in
                go(to: image.blockID)
            }
        }
    }

    private func header(_ landmark: ReaderDocument.Landmark?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(landmark?.title ?? "Images")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer()
            if let landmark {
                Button("Read") { go(to: landmark.blockID) }
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func grid(_ images: [ReaderDocument.Image]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 3)], spacing: 3) {
            ForEach(images) { image in
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { ArticleImage(id: image.metadata.id, aspectRatio: 1, contentMode: .fill) }
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture { galleryStart = image }
                    .contextMenu { menu(for: image) }
                    .accessibilityLabel(image.caption.isEmpty ? "Image" : image.caption)
                    .accessibilityAddTraits(.isButton)
            }
        }
        .padding(.horizontal, 3)
    }

    private func list(_ images: [ReaderDocument.Image]) -> some View {
        ForEach(images) { image in
            VStack(alignment: .leading, spacing: 8) {
                ArticleImage(id: image.metadata.id, aspectRatio: image.metadata.aspectRatio)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onTapGesture { galleryStart = image }
                    .contextMenu { menu(for: image) }
                if !image.caption.isEmpty {
                    Text(image.caption)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func menu(for image: ReaderDocument.Image) -> some View {
        Button("View Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") { galleryStart = image }
        Button("Show in Article", systemImage: "text.viewfinder") { go(to: image.blockID) }
    }

    private func go(to blockID: String) {
        dismiss()
        onShowInArticle(blockID)
    }
}
