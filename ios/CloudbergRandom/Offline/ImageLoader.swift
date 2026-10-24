import SwiftUI
import UIKit

/// An article image: the still to lay out and, when the image is animated, the
/// original bytes to play.
struct LoadedImage {
    let image: UIImage
    let animationData: Data?

    var cost: Int {
        let pixels = image.size.width * image.size.height * image.scale * image.scale
        return Int(pixels * 4) + (animationData?.count ?? 0)
    }
}

/// Loads article images from memory, then the offline library, then Medium.
actor ImageLoader {
    static let shared = ImageLoader()

    private final class CacheEntry {
        let loaded: LoadedImage
        init(_ loaded: LoadedImage) { self.loaded = loaded }
    }

    private let memory = NSCache<NSString, CacheEntry>()
    private var inFlight: [String: Task<LoadedImage, Error>] = [:]

    init() {
        memory.totalCostLimit = 150 * 1024 * 1024
    }

    func load(id: String) async throws -> LoadedImage {
        if let cached = memory.object(forKey: id as NSString) { return cached.loaded }
        if let task = inFlight[id] { return try await task.value }

        let task = Task.detached(priority: .userInitiated) { () throws -> LoadedImage in
            let data = try await Self.data(id: id)
            guard let first = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            // Animated images keep their bytes; decoding them to a single
            // UIImage is what flattened them to one frame.
            guard !AnimatedImage.isAnimated(data) else {
                return LoadedImage(image: first, animationData: data)
            }
            return LoadedImage(image: first.preparingForDisplay() ?? first, animationData: nil)
        }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        let loaded = try await task.value
        memory.setObject(CacheEntry(loaded), forKey: id as NSString, cost: loaded.cost)
        return loaded
    }

    /// Raw bytes for sharing/saving at full quality.
    nonisolated static func data(id: String) async throws -> Data {
        if let file = OfflineLibrary.localImageFile(id: id) { return try Data(contentsOf: file) }
        guard let url = MediumImage.url(id: id, width: OfflineLibrary.imageWidth) else { throw URLError(.badURL) }
        return try await URLSession.shared.data(from: url).0
    }
}

/// An article image that works offline when the article has been downloaded.
struct ArticleImage: View {
    let id: String
    var aspectRatio: CGFloat?
    var contentMode: ContentMode = .fit

    @State private var loaded: LoadedImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let loaded {
                if let animation = loaded.animationData {
                    AnimatedImageView(
                        data: animation,
                        contentMode: contentMode == .fill ? .scaleAspectFill : .scaleAspectFit
                    )
                    .aspectRatio(loaded.image.size.width / max(loaded.image.size.height, 1), contentMode: contentMode)
                } else {
                    Image(uiImage: loaded.image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .aspectRatio(aspectRatio ?? 16 / 9, contentMode: contentMode)
                    .overlay {
                        if failed {
                            Image(systemName: "photo").foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                        }
                    }
            }
        }
        .task(id: id) {
            do {
                loaded = try await ImageLoader.shared.load(id: id)
            } catch {
                failed = true
            }
        }
    }
}
