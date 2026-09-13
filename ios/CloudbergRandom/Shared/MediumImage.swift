import Foundation

enum MediumImage {
    /// Medium's image CDN URL for an image id, resized to fit `width` pixels.
    /// Requested as WebP: many article images are PNG diagrams that are ~10x
    /// larger in their original format.
    static func url(id: String, width: Int) -> URL? {
        guard !id.isEmpty else { return nil }
        return URL(string: "https://miro.medium.com/v2/format:webp/resize:fit:\(width)/\(id)")
    }
}
