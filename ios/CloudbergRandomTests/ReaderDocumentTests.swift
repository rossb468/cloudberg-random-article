import Foundation
import Testing
@testable import CloudbergRandom

struct ReaderDocumentTests {
    private func paragraph(_ id: String, _ kind: MediumParagraph.Kind, _ text: String = "",
                           layout: String? = nil, image: String? = nil) -> MediumParagraph {
        MediumParagraph(
            id: id, kind: kind, text: text, markups: [], layout: layout,
            image: image.map { MediumImageMetadata(id: $0, width: 100, height: 50, alt: nil) },
            href: nil, embed: nil
        )
    }

    private var document: ReaderDocument {
        let post = MediumPost(id: "post", title: "Title", paragraphs: [
            paragraph("h", .heading, "Title"),
            paragraph("cover", .image, "The wreck.", layout: "INSET_CENTER", image: "cover.jpg"),
            paragraph("p1", .paragraph, "On a dark and stormy night, the flight departed."),
            paragraph("brk", .paragraph, "◊◊◊"),
            paragraph("p2", .paragraph, "The investigation began the next morning with a search of the debris field."),
            paragraph("r1", .image, "", layout: "OUTSET_ROW", image: "a.jpg"),
            paragraph("r2", .image, "Two views.", layout: "OUTSET_ROW_CONTINUE", image: "b.jpg"),
            paragraph("o1", .orderedList, "First"),
            paragraph("o2", .orderedList, "Second"),
            paragraph("bib", .paragraph, "Bibliography"),
        ], fetchedAt: .now)
        return ReaderDocument(post: post, title: "Title")
    }

    @Test func skipsTheTitleHeading() {
        #expect(document.blocks.first?.id == "cover")
    }

    @Test func turnsDiamondsIntoSectionLandmarks() throws {
        let section = try #require(document.landmarks.first { $0.kind == .section })
        #expect(section.blockID == "brk")
        #expect(section.title.hasPrefix("The investigation began"))
        #expect(document.landmarks.first?.kind == .start)
        #expect(document.landmarks.last?.title == "Bibliography")
    }

    @Test func groupsImageRowsWithTheLastCaption() throws {
        let row = try #require(document.blocks.first { $0.id == "r1" })
        guard case .figure(let images, let caption, _, .row) = row.content else {
            Issue.record("expected an image row, got \(row.content)")
            return
        }
        #expect(images.map(\.id) == ["a.jpg", "b.jpg"])
        #expect(caption == "Two views.")
        #expect(document.images.map(\.metadata.id) == ["cover.jpg", "a.jpg", "b.jpg"])
    }

    @Test func numbersOrderedLists() {
        let styles = document.blocks.compactMap { block -> ReaderDocument.TextStyle? in
            if case .text(let style, _, _) = block.content { return style }
            return nil
        }
        #expect(styles.contains(.numbered(1)))
        #expect(styles.contains(.numbered(2)))
    }

    @Test func progressIsMonotonicAndInvertible() {
        let doc = document
        #expect(doc.progressAtBlock.first == 0)
        #expect(zip(doc.progressAtBlock, doc.progressAtBlock.dropFirst()).allSatisfy { $0 < $1 })
        for block in doc.blocks {
            #expect(doc.blockID(atProgress: doc.progress(at: block.id)) == block.id)
        }
    }

    @Test func excerptsTrimAtWordBoundaries() {
        let long = String(repeating: "word ", count: 40)
        #expect(ReaderDocument.openingWords(long, limit: 22) == "word word word word…")
    }
}
