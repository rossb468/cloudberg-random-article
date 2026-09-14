import Foundation
import Testing
@testable import CloudbergRandom

struct MediumClientTests {
    /// A trimmed-down page shaped like Medium's: the Apollo cache assigned to
    /// `window.__APOLLO_STATE__`, with paragraphs referenced from the post body.
    private let page = #"""
    <html><head><script>window.__APOLLO_STATE__ = {
      "Post:abc123def456": {
        "__typename": "Post", "id": "abc123def456", "title": "A Test Article", "isLocked": false,
        "clapCount": 42, "postResponses": {"__typename": "PostResponses", "count": 7},
        "content({\"postMeteringOptions\":{\"referrer\":\"\"}})": {
          "bodyModel": { "paragraphs": [
            {"__ref": "Paragraph:p_0"}, {"__ref": "Paragraph:p_1"}, {"__ref": "Paragraph:p_2"}, {"__ref": "Paragraph:p_3"},
            {"__ref": "Paragraph:p_4"}
          ]}
        }
      },
      "Paragraph:p_0": {"id": "p_0", "type": "H3", "text": "A Test Article", "markups": []},
      "Paragraph:p_1": {"id": "p_1", "type": "IMG", "text": "Caption {with braces}", "layout": "INSET_CENTER", "markups": [],
                        "metadata": {"__ref": "ImageMetadata:1*abc.jpeg"}},
      "ImageMetadata:1*abc.jpeg": {"id": "1*abc.jpeg", "originalWidth": 1600, "originalHeight": 900, "alt": null},
      "Paragraph:p_2": {"id": "p_2", "type": "P", "text": "Some \"quoted\" and linked text.", "markups": [
        {"type": "EM", "start": 5, "end": 13, "href": null},
        {"type": "A", "start": 18, "end": 24, "href": "https://example.com"}
      ]},
      "Paragraph:p_3": {"id": "p_3", "type": "SOMETHING_NEW", "text": "?", "markups": []},
      "Paragraph:p_4": {"id": "p_4", "type": "IFRAME", "text": "Watch the video", "markups": [],
                        "iframe": {"__typename": "Iframe", "mediaResource": {"__ref": "MediaResource:m1"}}},
      "MediaResource:m1": {"id": "m1", "title": "A video",
        "iframeSrc": "https://cdn.embedly.com/widgets/media.html?src=x&url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3Dabc&image=https%3A%2F%2Fi.ytimg.com%2Fvi%2Fabc%2Fhq.jpg"}
    };</script><script>window.__MIDDLEWARE_STATE__ = {}</script></head></html>
    """#

    @Test func extractsApolloStateDespiteBracesInStrings() throws {
        let json = try #require(MediumClient.apolloStateJSON(in: Data(page.utf8)))
        let object = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        #expect(object?["Paragraph:p_1"] != nil)
    }

    @Test func parsesParagraphsInBodyOrder() throws {
        let post = try MediumClient.parsePost(html: Data(page.utf8), postID: "abc123def456")
        #expect(post.title == "A Test Article")
        #expect(post.paragraphs.map(\.kind) == [.heading, .image, .paragraph, .unknown, .embed])
    }

    @Test func resolvesImageMetadataReferences() throws {
        let post = try MediumClient.parsePost(html: Data(page.utf8), postID: "abc123def456")
        let image = try #require(post.paragraphs[1].image)
        #expect(image.id == "1*abc.jpeg")
        #expect(abs((image.aspectRatio ?? 0) - 16.0 / 9.0) < 0.0001)
        #expect(post.imageIDs == ["1*abc.jpeg"])
    }

    @Test func keepsMarkups() throws {
        let post = try MediumClient.parsePost(html: Data(page.utf8), postID: "abc123def456")
        let markups = post.paragraphs[2].markups
        #expect(markups.map(\.kind) == [.italic, .link])
        #expect(markups[1].href == "https://example.com")
    }

    @Test func unwrapsEmbedURLs() throws {
        let post = try MediumClient.parsePost(html: Data(page.utf8), postID: "abc123def456")
        let embed = try #require(post.paragraphs[4].embed)
        #expect(embed.url == "https://www.youtube.com/watch?v=abc")
        #expect(embed.thumbnailURL == "https://i.ytimg.com/vi/abc/hq.jpg")
        #expect(embed.title == "A video")
    }

    @Test func readsEngagement() throws {
        let post = try MediumClient.parsePost(html: Data(page.utf8), postID: "abc123def456")
        #expect(post.clapCount == 42)
        #expect(post.responseCount == 7)
        #expect(MediumClient.parseEngagement(html: Data(page.utf8), postID: "abc123def456") == .init(claps: 42, responses: 7))
    }

    @Test func missingPostThrows() {
        #expect(throws: MediumClientError.self) {
            try MediumClient.parsePost(html: Data(page.utf8), postID: "nope")
        }
    }

    @Test func savedPostRoundTrips() throws {
        let post = try MediumClient.parsePost(html: Data(page.utf8), postID: "abc123def456", fetchedAt: Date(timeIntervalSince1970: 0))
        let decoded = try JSONDecoder().decode(MediumPost.self, from: JSONEncoder().encode(post))
        #expect(decoded == post)
    }
}
