import SwiftUI
import UIKit

/// Full-screen image viewer: swipe between an article's images, pinch or
/// double-tap to zoom, and save, share or copy each image.
struct ImageGalleryView: View {
    let images: [ReaderDocument.Image]
    var onShowInArticle: (ReaderDocument.Image) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var selection: String
    @State private var chromeVisible = true
    @State private var loaded: [String: LoadedImage] = [:]
    @State private var toast: String?

    init(images: [ReaderDocument.Image], startingAt start: ReaderDocument.Image,
         onShowInArticle: @escaping (ReaderDocument.Image) -> Void = { _ in }) {
        self.images = images
        self.onShowInArticle = onShowInArticle
        _selection = State(initialValue: start.id)
    }

    private var current: ReaderDocument.Image? {
        images.first { $0.id == selection }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(images) { image in
                    ZoomableImage(loaded: loaded[image.metadata.id])
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { chromeVisible.toggle() } }
                        .task { await load(image) }
                        .tag(image.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            if chromeVisible {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    bottomBar
                }
                .transition(.opacity)
            }

            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(!chromeVisible)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
            Spacer()
            if let index = images.firstIndex(where: { $0.id == selection }) {
                Text("\(index + 1) of \(images.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
        .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let caption = current?.caption, !caption.isEmpty {
                ScrollView {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if let current, let loaded = loaded[current.metadata.id] {
                    let preview = SharePreview(current.caption.isEmpty ? "Image" : current.caption,
                                               image: Image(uiImage: loaded.image))
                    if let animation = loaded.animationData {
                        ShareLink(item: ShareableAnimatedImage(data: animation), preview: preview) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        ShareLink(item: ShareableImage(image: loaded.image), preview: preview) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    Spacer()
                    Button { save(current) } label: { Label("Save", systemImage: "square.and.arrow.down") }
                    Spacer()
                    Button { copy(current) } label: { Label("Copy", systemImage: "doc.on.doc") }
                    Spacer()
                    Button {
                        dismiss()
                        onShowInArticle(current)
                    } label: {
                        Label("In Article", systemImage: "text.viewfinder")
                    }
                } else {
                    ProgressView()
                }
            }
            .labelStyle(VerticalLabelStyle())
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .padding(.bottom, 8)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private func load(_ image: ReaderDocument.Image) async {
        guard loaded[image.metadata.id] == nil else { return }
        loaded[image.metadata.id] = try? await ImageLoader.shared.load(id: image.metadata.id)
    }

    private func save(_ image: ReaderDocument.Image) {
        Task {
            let saved = await ImageActions.save(id: image.metadata.id)
            show(saved ? "Saved to Photos" : "Couldn't save — check Photos access in Settings")
        }
    }

    private func copy(_ image: ReaderDocument.Image) {
        Task {
            await ImageActions.copy(id: image.metadata.id)
            show("Copied")
        }
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { toast = nil }
        }
    }
}

private struct VerticalLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 4) {
            configuration.icon.font(.title3)
            configuration.title.font(.caption2)
        }
    }
}

/// Exports as JPEG, which every share target accepts (the cached image may be WebP).
struct ShareableImage: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { item in
            item.image.jpegData(compressionQuality: 0.92) ?? Data()
        }
    }
}

enum PhotoLibrarySaver {
    @MainActor
    static func save(_ image: UIImage) async -> Bool {
        await withCheckedContinuation { continuation in
            let target = Target(continuation: continuation)
            UIImageWriteToSavedPhotosAlbum(image, target, #selector(Target.image(_:didFinishSavingWithError:contextInfo:)), nil)
            // UIKit doesn't retain the target; keep it alive until the callback.
            objc_setAssociatedObject(image, &Target.key, target, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    private final class Target: NSObject {
        nonisolated(unsafe) static var key: UInt8 = 0
        let continuation: CheckedContinuation<Bool, Never>

        init(continuation: CheckedContinuation<Bool, Never>) {
            self.continuation = continuation
        }

        @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer?) {
            continuation.resume(returning: error == nil)
        }
    }
}

/// A UIScrollView-backed image for smooth pinch and double-tap zooming, which
/// keeps animating while you zoom.
struct ZoomableImage: UIViewRepresentable {
    let loaded: LoadedImage?

    func makeUIView(context: Context) -> ZoomingScrollView {
        ZoomingScrollView()
    }

    func updateUIView(_ view: ZoomingScrollView, context: Context) {
        view.show(loaded)
    }

    final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
        private let imageView = AnimatedImageHostView()
        private let spinner = UIActivityIndicatorView(style: .large)

        override init(frame: CGRect) {
            super.init(frame: frame)
            delegate = self
            minimumZoomScale = 1
            maximumZoomScale = 5
            showsVerticalScrollIndicator = false
            showsHorizontalScrollIndicator = false
            contentInsetAdjustmentBehavior = .never
            imageView.contentMode = .scaleAspectFit
            imageView.isAccessibilityElement = true
            addSubview(imageView)
            spinner.color = .white
            addSubview(spinner)

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
            doubleTap.numberOfTapsRequired = 2
            addGestureRecognizer(doubleTap)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func show(_ loaded: LoadedImage?) {
            guard let loaded else {
                spinner.startAnimating()
                return
            }
            if let animation = loaded.animationData {
                imageView.play(animation)
            } else {
                guard imageView.image !== loaded.image else { return }
                imageView.image = loaded.image
            }
            spinner.stopAnimating()
            zoomScale = 1
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
            if zoomScale == 1 {
                imageView.frame = bounds
                contentSize = bounds.size
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
            if zoomScale > 1 {
                setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
                zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
        }
    }
}
