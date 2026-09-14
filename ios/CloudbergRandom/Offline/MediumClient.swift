import Foundation

enum MediumClientError: LocalizedError {
    case httpStatus(Int)
    case missingArticleData
    case articleLocked

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status): "Medium returned HTTP \(status)."
        case .missingArticleData: "Couldn't find the article text in Medium's page."
        case .articleLocked: "This article is members-only on Medium."
        }
    }
}

/// Fetches article pages from Medium and pulls the structured article body out
/// of the Apollo cache Medium embeds in every page (`window.__APOLLO_STATE__`).
struct MediumClient {
    var session: URLSession = .shared

    // Medium's Cloudflare rules are stricter for non-browser user agents.
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    struct Engagement: Equatable {
        let claps: Int
        let responses: Int
    }

    func fetchPost(for article: Article) async throws -> MediumPost {
        try Self.parsePost(html: try await fetchPage(for: article), postID: article.postID)
    }

    /// Just the clap and response counts from an article page.
    func fetchEngagement(for article: Article) async throws -> Engagement {
        guard let engagement = Self.parseEngagement(html: try await fetchPage(for: article), postID: article.postID) else {
            throw MediumClientError.missingArticleData
        }
        return engagement
    }

    private func fetchPage(for article: Article) async throws -> Data {
        guard let url = article.webURL else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard status == 200 else { throw MediumClientError.httpStatus(status) }
        return data
    }

    static func parseEngagement(html: Data, postID: String) -> Engagement? {
        guard let stateData = apolloStateJSON(in: html),
              let state = try? JSONSerialization.jsonObject(with: stateData) as? [String: Any],
              let post = state["Post:\(postID)"] as? [String: Any] else { return nil }
        return engagement(in: post)
    }

    private static func engagement(in post: [String: Any]) -> Engagement? {
        guard let claps = post["clapCount"] as? Int else { return nil }
        let responses = (post["postResponses"] as? [String: Any])?["count"] as? Int ?? 0
        return Engagement(claps: claps, responses: responses)
    }

    static func parsePost(html: Data, postID: String, fetchedAt: Date = .now) throws -> MediumPost {
        guard let stateData = apolloStateJSON(in: html),
              let state = try JSONSerialization.jsonObject(with: stateData) as? [String: Any],
              let post = state["Post:\(postID)"] as? [String: Any]
        else { throw MediumClientError.missingArticleData }

        if post["isLocked"] as? Bool == true { throw MediumClientError.articleLocked }

        // The body lives under a key with arguments baked in, e.g.
        // `content({"postMeteringOptions":{"referrer":""}})`.
        guard let contentKey = post.keys.first(where: { $0.hasPrefix("content") }),
              let content = post[contentKey] as? [String: Any],
              let body = content["bodyModel"] as? [String: Any],
              let refs = body["paragraphs"] as? [[String: Any]]
        else { throw MediumClientError.missingArticleData }

        let paragraphs = refs.compactMap { ref -> MediumParagraph? in
            guard let key = ref["__ref"] as? String, let raw = state[key] as? [String: Any] else { return nil }
            return paragraph(from: raw, state: state)
        }
        guard !paragraphs.isEmpty else { throw MediumClientError.missingArticleData }

        let engagement = engagement(in: post)
        return MediumPost(
            id: postID,
            title: post["title"] as? String ?? "",
            paragraphs: paragraphs,
            fetchedAt: fetchedAt,
            clapCount: engagement?.claps,
            responseCount: engagement?.responses
        )
    }

    private static func paragraph(from raw: [String: Any], state: [String: Any]) -> MediumParagraph? {
        guard let id = raw["id"] as? String else { return nil }
        // Decode the kind through Codable so unknown types map to `.unknown`.
        let kindString = raw["type"] as? String ?? ""
        let kind = (try? JSONDecoder().decode(MediumParagraph.Kind.self, from: Data("\"\(kindString)\"".utf8))) ?? .unknown

        let markups = (raw["markups"] as? [[String: Any]] ?? []).compactMap { markup -> MediumMarkup? in
            guard let start = markup["start"] as? Int, let end = markup["end"] as? Int else { return nil }
            let type = markup["type"] as? String ?? ""
            return MediumMarkup(
                kind: MediumMarkup.Kind(rawValue: type) ?? .unknown,
                start: start,
                end: end,
                href: markup["href"] as? String
            )
        }

        var image: MediumImageMetadata?
        if let metadata = resolve(raw["metadata"], in: state), let imageID = metadata["id"] as? String, !imageID.isEmpty {
            image = MediumImageMetadata(
                id: imageID,
                width: metadata["originalWidth"] as? Int,
                height: metadata["originalHeight"] as? Int,
                alt: metadata["alt"] as? String
            )
        }

        var href = raw["href"] as? String
        if href == nil, let mixtape = resolve(raw["mixtapeMetadata"], in: state) {
            href = mixtape["href"] as? String
        }

        var embed: MediumEmbed?
        if let iframe = resolve(raw["iframe"], in: state),
           let resource = resolve(iframe["mediaResource"], in: state),
           let source = resource["iframeSrc"] as? String {
            // Medium wraps embeds in an embed.ly URL that carries the original.
            let query = URLComponents(string: source)?.queryItems ?? []
            embed = MediumEmbed(
                url: query.first { $0.name == "url" }?.value ?? source,
                thumbnailURL: query.first { $0.name == "image" }?.value,
                title: resource["title"] as? String
            )
        }

        return MediumParagraph(
            id: id,
            kind: kind,
            text: raw["text"] as? String ?? "",
            markups: markups,
            layout: raw["layout"] as? String,
            image: image,
            href: href,
            embed: embed
        )
    }

    /// Apollo stores nested objects either inline or as `{"__ref": "Type:id"}`.
    private static func resolve(_ value: Any?, in state: [String: Any]) -> [String: Any]? {
        guard let object = value as? [String: Any] else { return nil }
        if let ref = object["__ref"] as? String { return state[ref] as? [String: Any] }
        return object
    }

    /// The raw JSON of the object assigned to `window.__APOLLO_STATE__`.
    static func apolloStateJSON(in html: Data) -> Data? {
        let bytes = [UInt8](html)
        guard let marker = bytes.firstRange(of: Array("window.__APOLLO_STATE__".utf8)),
              let open = bytes[marker.upperBound...].firstIndex(of: UInt8(ascii: "{"))
        else { return nil }

        var depth = 0
        var inString = false
        var escaped = false
        for index in open..<bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped { escaped = false }
                else if byte == UInt8(ascii: "\\") { escaped = true }
                else if byte == UInt8(ascii: "\"") { inString = false }
            } else if byte == UInt8(ascii: "\"") {
                inString = true
            } else if byte == UInt8(ascii: "{") {
                depth += 1
            } else if byte == UInt8(ascii: "}") {
                depth -= 1
                if depth == 0 { return Data(bytes[open...index]) }
            }
        }
        return nil
    }
}
