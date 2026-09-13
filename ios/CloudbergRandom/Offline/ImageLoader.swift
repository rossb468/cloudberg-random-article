import SwiftUI
import UIKit

/// Loads article images from memory, then the offline library, then Medium.
actor ImageLoader {
    static let shared = ImageLoader()

    private let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage, Error>] = [:]

    init() {
        memory.totalCostLimit = 150 * 1024 * 1024
    }

    func image(id: String) async throws -> UIImage {
        if let cached = memory.object(forKey: id as NSString) { return cached }
        if let task = inFlight[id] { return try await task.value }

        let task = Task.detached(priority: .userInitiated) { () throws -> UIImage in
            let data: Data
            if let file = OfflineLibrary.localImageFile(id: id) {
                data = try Data(contentsOf: file)
            } else {
                guard let url = MediumImage.url(id: id, width: OfflineLibrary.imageWidth) else { throw URLError(.badURL) }
                data = try await URLSession.shared.data(from: url).0
            }
            guard let image = UIImage(data: data)?.preparingForDisplay() ?? UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            return image
        }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        let image = try await task.value
        memory.setObject(image, forKey: id as NSString, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        return image
    }

    /// Raw bytes for sharing/saving at full quality.
    func data(id: String) async throws -> Data {
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

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
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
                image = try await ImageLoader.shared.image(id: id)
            } catch {
                failed = true
            }
        }
    }
}
