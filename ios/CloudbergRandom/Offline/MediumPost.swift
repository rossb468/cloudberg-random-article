import Foundation

/// A Medium article's body as Medium itself structures it: an ordered list of
/// paragraphs (text, headings, images, quotes) with inline markup ranges.
/// This is what gets saved for offline reading.
struct MediumPost: Codable, Equatable {
    let id: String
    let title: String
    let paragraphs: [MediumParagraph]
    let fetchedAt: Date

    var imageIDs: [String] {
        paragraphs.compactMap { $0.image?.id }.filter { !$0.isEmpty }
    }
}

struct MediumParagraph: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case paragraph = "P"
        case heading = "H3"
        case subheading = "H4"
        case image = "IMG"
        case blockquote = "BQ"
        case pullQuote = "PQ"
        case bulletedList = "ULI"
        case orderedList = "OLI"
        case code = "PRE"
        case embed = "IFRAME"
        case linkPreview = "MIXTAPE_EMBED"
        case unknown

        init(from decoder: Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    let id: String
    let kind: Kind
    let text: String
    let markups: [MediumMarkup]
    /// INSET_CENTER, OUTSET_CENTER, FULL_WIDTH, ... for images.
    let layout: String?
    let image: MediumImageMetadata?
    /// Link target for link previews.
    let href: String?
    /// Video or other embedded media.
    let embed: MediumEmbed?
}

struct MediumEmbed: Codable, Equatable {
    /// The embedded page itself (e.g. a YouTube watch URL), not Medium's embed wrapper.
    let url: String
    let thumbnailURL: String?
    let title: String?
}

struct MediumMarkup: Codable, Equatable {
    enum Kind: String, Codable {
        case link = "A"
        case bold = "STRONG"
        case italic = "EM"
        case code = "CODE"
        case unknown

        init(from decoder: Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    let kind: Kind
    /// UTF-16 offsets into the paragraph text, as Medium's web client uses them.
    let start: Int
    let end: Int
    let href: String?
}

struct MediumImageMetadata: Codable, Equatable {
    let id: String
    let width: Int?
    let height: Int?
    let alt: String?

    var aspectRatio: CGFloat? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return CGFloat(width) / CGFloat(height)
    }
}
