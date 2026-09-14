import Foundation
import Testing
@testable import CloudbergRandom

struct ReaderNavigationTests {
    private var document: ReaderDocument {
        func p(_ id: String, _ text: String) -> MediumParagraph {
            MediumParagraph(id: id, kind: .paragraph, text: text, markups: [], layout: nil, image: nil, href: nil, embed: nil)
        }
        let post = MediumPost(id: "post", title: "Title", paragraphs: [
            p("p0", "Intro paragraph with enough words to matter."),
            p("p1", "More of the introduction."),
            p("s1", "◊◊◊"),
            p("p3", "The second section begins here."),
            p("p4", "It continues."),
            p("s2", "◊◊◊"),
            p("p6", "The final section."),
            p("p7", "The end."),
        ], fetchedAt: .now)
        return ReaderDocument(post: post, title: "Title")
    }

    private let bookmarks = [Bookmark(blockID: "p4", excerpt: "It continues.")]

    @Test func stopsMergeSectionsAndBookmarksInOrder() {
        let stops = document.stops(bookmarks: bookmarks)
        #expect(stops.map(\.blockID) == ["p0", "s1", "p4", "s2"])
        #expect(stops.map(\.kind) == [.landmark, .landmark, .bookmark, .landmark])
    }

    @Test func nextAndPreviousSkipBetweenStops() {
        let doc = document
        #expect(doc.nextStop(after: "p1", bookmarks: bookmarks)?.blockID == "s1")
        #expect(doc.nextStop(after: "p3", bookmarks: bookmarks)?.blockID == "p4")
        #expect(doc.nextStop(after: "p7", bookmarks: bookmarks) == nil)
        #expect(doc.previousStop(before: "p6", bookmarks: bookmarks)?.blockID == "s2")
        #expect(doc.previousStop(before: "s2", bookmarks: bookmarks)?.blockID == "p4")
        #expect(doc.previousStop(before: "p0", bookmarks: bookmarks) == nil)
    }

    @Test func bookmarksOnMissingBlocksAreIgnored() {
        let stale = [Bookmark(blockID: "gone", excerpt: "")]
        #expect(document.stops(bookmarks: stale).count == document.landmarks.count)
    }

    @Test func findsTheContainingSection() {
        #expect(document.landmark(containing: "p4")?.blockID == "s1")
        #expect(document.landmark(containing: "p0")?.kind == .start)
    }
}
