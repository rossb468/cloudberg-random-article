import Foundation

/// An article prepared for reading: Medium's paragraphs grouped into blocks the
/// reader can lay out, plus the landmarks, images and progress used for
/// navigation.
struct ReaderDocument {
    struct Block: Identifiable, Equatable {
        enum Content: Equatable {
            case text(TextStyle, String, [MediumMarkup])
            case figure([MediumImageMetadata], caption: String, captionMarkups: [MediumMarkup], layout: FigureLayout)
            case sectionBreak
            case embed(MediumEmbed, caption: String)
            case link(url: String, title: String)
        }

        /// The id of the first Medium paragraph in the block. Stable across
        /// re-downloads, so it's what reading positions and bookmarks store.
        let id: String
        let index: Int
        let content: Content
    }

    enum TextStyle: Equatable {
        case body, heading, subheading, blockquote, pullQuote, bullet, numbered(Int), code
    }

    enum FigureLayout: Equatable {
        case inset, wide, row
    }

    struct Landmark: Identifiable, Equatable {
        enum Kind: Equatable { case start, heading, section }
        let blockID: String
        let blockIndex: Int
        let title: String
        let kind: Kind
        var id: String { blockID }
    }

    struct Image: Identifiable, Equatable {
        let metadata: MediumImageMetadata
        let caption: String
        let blockID: String
        var id: String { "\(blockID)/\(metadata.id)" }
    }

    let title: String
    let blocks: [Block]
    let landmarks: [Landmark]
    let images: [Image]
    /// Fraction of the article's text that comes before each block.
    let progressAtBlock: [Double]

    /// Paragraph texts that mark a section break in Admiral Cloudberg's articles.
    static let sectionBreakMarkers: Set<String> = ["◊◊◊", "◊ ◊ ◊", "***", "* * *"]
    /// "◊◊◊" and friends, or a rule drawn with divider characters (underscores,
    /// dashes). Not other punctuation-only lines, like a transcript's “...”.
    static func isSectionBreak(_ text: String) -> Bool {
        sectionBreakMarkers.contains(text)
            || (text.count >= 3 && text.allSatisfy { "_-–—=*◊·•~ ".contains($0) })
    }

    /// Plain paragraphs that act as headings.
    static let headingLikeParagraphs: Set<String> = ["Bibliography", "Sources", "References", "Notes"]

    init(post: MediumPost, title: String) {
        self.title = title
        var blocks: [Block] = []
        var listNumber = 0

        func append(_ content: Block.Content, id: String) {
            blocks.append(Block(id: id, index: blocks.count, content: content))
        }

        for (offset, paragraph) in post.paragraphs.enumerated() {
            let text = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
            listNumber = paragraph.kind == .orderedList ? listNumber + 1 : 0

            switch paragraph.kind {
            case .heading where offset == 0 && Self.sameTitle(text, title):
                continue // The reader shows the title itself.
            case .heading:
                append(.text(.heading, text, paragraph.markups), id: paragraph.id)
            case .subheading:
                append(.text(.subheading, text, paragraph.markups), id: paragraph.id)
            case .paragraph where Self.isSectionBreak(text):
                // "◊◊◊" is sometimes followed by a rule of underscores; one break is enough.
                if case .sectionBreak? = blocks.last?.content { continue }
                append(.sectionBreak, id: paragraph.id)
            case .paragraph where Self.headingLikeParagraphs.contains(text):
                append(.text(.heading, text, []), id: paragraph.id)
            case .paragraph, .unknown:
                guard !text.isEmpty else { continue }
                append(.text(.body, paragraph.text, paragraph.markups), id: paragraph.id)
            case .blockquote:
                append(.text(.blockquote, paragraph.text, paragraph.markups), id: paragraph.id)
            case .pullQuote:
                append(.text(.pullQuote, paragraph.text, paragraph.markups), id: paragraph.id)
            case .bulletedList:
                append(.text(.bullet, paragraph.text, paragraph.markups), id: paragraph.id)
            case .orderedList:
                append(.text(.numbered(listNumber), paragraph.text, paragraph.markups), id: paragraph.id)
            case .code:
                append(.text(.code, paragraph.text, paragraph.markups), id: paragraph.id)
            case .image:
                guard let image = paragraph.image else { continue }
                // Medium lays out OUTSET_ROW + OUTSET_ROW_CONTINUE images side by side,
                // captioned by the last image in the row.
                if paragraph.layout == "OUTSET_ROW_CONTINUE",
                   let last = blocks.last,
                   case .figure(let images, let caption, let markups, .row) = last.content {
                    let useNew = !text.isEmpty
                    blocks[blocks.count - 1] = Block(
                        id: last.id, index: last.index,
                        content: .figure(images + [image],
                                         caption: useNew ? paragraph.text : caption,
                                         captionMarkups: useNew ? paragraph.markups : markups,
                                         layout: .row)
                    )
                } else {
                    let layout: FigureLayout = switch paragraph.layout {
                    case "OUTSET_ROW": .row
                    case "OUTSET_CENTER", "FULL_WIDTH": .wide
                    default: .inset
                    }
                    append(.figure([image], caption: paragraph.text, captionMarkups: paragraph.markups, layout: layout), id: paragraph.id)
                }
            case .embed:
                if let embed = paragraph.embed {
                    append(.embed(embed, caption: paragraph.text), id: paragraph.id)
                } else if let href = paragraph.href {
                    append(.link(url: href, title: text.isEmpty ? href : text), id: paragraph.id)
                }
            case .linkPreview:
                if let href = paragraph.href {
                    append(.link(url: href, title: text.isEmpty ? href : text), id: paragraph.id)
                }
            }
        }
        self.blocks = blocks

        var landmarks: [Landmark] = []
        if let first = blocks.first {
            landmarks.append(Landmark(blockID: first.id, blockIndex: 0, title: "Beginning", kind: .start))
        }
        var sectionNumber = 1
        for block in blocks {
            switch block.content {
            case .text(.heading, let text, _), .text(.subheading, let text, _):
                landmarks.append(Landmark(blockID: block.id, blockIndex: block.index, title: text, kind: .heading))
            case .sectionBreak:
                sectionNumber += 1
                let preview = blocks.dropFirst(block.index + 1).lazy.compactMap(Self.bodyText).first
                let title = preview.map { Self.openingWords($0) } ?? "Part \(sectionNumber)"
                landmarks.append(Landmark(blockID: block.id, blockIndex: block.index, title: title, kind: .section))
            default:
                break
            }
        }
        self.landmarks = landmarks

        images = blocks.flatMap { block -> [Image] in
            guard case .figure(let images, let caption, _, _) = block.content else { return [] }
            return images.map { Image(metadata: $0, caption: caption, blockID: block.id) }
        }

        // Weight progress by text length, with a nominal size for figures, so
        // "40%" means roughly 40% of the reading.
        let weights = blocks.map { block -> Double in
            switch block.content {
            case .text(_, let text, _): Double(max(text.count, 40))
            case .figure: 300
            default: 80
            }
        }
        let total = max(weights.reduce(0, +), 1)
        var running = 0.0
        progressAtBlock = weights.map { weight in
            defer { running += weight }
            return running / total
        }
    }

    func index(of blockID: String) -> Int? {
        blocks.firstIndex { $0.id == blockID }
    }

    func progress(at blockID: String) -> Double {
        index(of: blockID).map { progressAtBlock[$0] } ?? 0
    }

    /// The block closest to a fraction of the way through the article.
    func blockID(atProgress progress: Double) -> String? {
        guard !blocks.isEmpty else { return nil }
        let index = progressAtBlock.lastIndex { $0 <= progress } ?? 0
        return blocks[index].id
    }

    /// Short excerpt for bookmarks.
    func excerpt(at blockID: String) -> String {
        guard let index = index(of: blockID) else { return "" }
        let text = blocks[index...].lazy.compactMap { block -> String? in
            switch block.content {
            case .text(_, let text, _): text
            case .figure(_, let caption, _, _) where !caption.isEmpty: caption
            default: nil
            }
        }.first ?? ""
        return Self.openingWords(text)
    }

    private static func bodyText(_ block: Block) -> String? {
        if case .text(.body, let text, _) = block.content { return text }
        return nil
    }

    static func openingWords(_ text: String, limit: Int = 70) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let cut = trimmed.prefix(limit)
        let end = cut.lastIndex(of: " ") ?? cut.endIndex
        return String(cut[..<end]) + "…"
    }

    private static func sameTitle(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
