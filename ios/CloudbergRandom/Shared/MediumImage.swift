import Foundation

enum MediumImage {
    /// Medium's image CDN URL for an image id, resized to fit `width` points.
    static func url(id: String, width: Int) -> URL? {
        guard !id.isEmpty else { return nil }
        return URL(string: "https://miro.medium.com/v2/resize:fit:\(width)/\(id)")
    }
}
