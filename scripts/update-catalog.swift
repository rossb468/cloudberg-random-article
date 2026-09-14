#!/usr/bin/env swift
// Refreshes the article catalog from Admiral Cloudberg's Medium pages.
//
//   swift scripts/update-catalog.swift [--cache-dir DIR]
//
// Articles come from the existing catalog plus anything new in Medium's sitemap
// (the sitemap alone is incomplete — it omits many older articles). Each page is
// re-fetched for current metadata.
//
// Writes ios/CloudbergRandom/Resources/articles.json and app/data.js. Only
// metadata is written (title, subtitle, dates, length, cover image id, clap and
// response counts) — article text is never stored in the repo.
//
// This is a Swift script on purpose: Medium's Cloudflare rules reject curl's and
// Python's TLS fingerprints but accept Apple's URLSession.

import Foundation

let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let catalogFile = repoRoot.appendingPathComponent("ios/CloudbergRandom/Resources/articles.json")
let sitemapURL = URL(string: "https://admiralcloudberg.medium.com/sitemap/sitemap.xml")!
let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

/// Standalone posts shorter than this (progress updates, announcements) aren't articles.
let minimumArticleWords = 1000

/// Non-article posts long enough to get past `minimumArticleWords`.
let excludedPostIDs: Set<String> = [
    "24f9093cbc40", // Progress Update: New article coming soon, and a teaser
]

var cacheDir: URL?
if let i = CommandLine.arguments.firstIndex(of: "--cache-dir"), i + 1 < CommandLine.arguments.count {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1], isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    cacheDir = dir
}

func fetch(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    for attempt in 1...4 {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 200 { return data }
        if status == 404 { break }
        try await Task.sleep(nanoseconds: UInt64(attempt * attempt) * 1_000_000_000)
    }
    throw URLError(.badServerResponse)
}

func page(_ url: URL, postID: String) async throws -> Data {
    guard let cacheDir else { return try await fetch(url) }
    let file = cacheDir.appendingPathComponent("\(postID).html")
    if let data = try? Data(contentsOf: file) { return data }
    let data = try await fetch(url)
    try data.write(to: file)
    return data
}

/// The JSON object assigned to `window.__APOLLO_STATE__` in a Medium page.
func apolloState(in html: Data) -> [String: Any]? {
    let bytes = [UInt8](html)
    guard let marker = bytes.firstRange(of: Array("window.__APOLLO_STATE__".utf8)),
          let open = bytes[marker.upperBound...].firstIndex(of: UInt8(ascii: "{")) else { return nil }
    var depth = 0, inString = false, escaped = false
    for i in open..<bytes.count {
        let c = bytes[i]
        if inString {
            if escaped { escaped = false }
            else if c == UInt8(ascii: "\\") { escaped = true }
            else if c == UInt8(ascii: "\"") { inString = false }
            continue
        }
        if c == UInt8(ascii: "\"") { inString = true }
        else if c == UInt8(ascii: "{") { depth += 1 }
        else if c == UInt8(ascii: "}") {
            depth -= 1
            if depth == 0 {
                return try? JSONSerialization.jsonObject(with: Data(bytes[open...i])) as? [String: Any]
            }
        }
    }
    return nil
}

/// Medium post ids are the hex suffix after the slug's last hyphen (8–12 digits).
func postID(from url: String) -> String? {
    guard let range = url.range(of: "-[0-9a-f]{8,12}$", options: .regularExpression) else { return nil }
    return String(url[range].dropFirst())
}

struct CatalogEntry: Codable {
    let title: String
    let subtitle: String
    let url: String
    let wordCount: Int
    let readingTime: Double
    let publishedAt: Int64
    let image: String
    /// Medium engagement when the catalog was generated. Optional so catalogs
    /// written before these existed still load as the starting point.
    let claps: Int?
    let responses: Int?
}

func entry(for pageURL: String) async -> CatalogEntry? {
    guard let id = postID(from: pageURL), !excludedPostIDs.contains(id), let url = URL(string: pageURL) else { return nil }
    do {
        guard let state = apolloState(in: try await page(url, postID: id)),
              let post = state["Post:\(id)"] as? [String: Any],
              let title = post["title"] as? String,
              let publishedAt = post["firstPublishedAt"] as? NSNumber else {
            FileHandle.standardError.write(Data("! no post data: \(pageURL)\n".utf8))
            return nil
        }
        // Responses (comments) share the sitemap with articles.
        if let parent = post["inResponseToPostResult"], !(parent is NSNull) { return nil }
        let wordCount = (post["wordCount"] as? NSNumber)?.intValue ?? 0
        guard wordCount >= minimumArticleWords else { return nil }
        let readingTime = (post["readingTime"] as? NSNumber)?.doubleValue ?? 0
        return CatalogEntry(
            title: title,
            subtitle: ((post["previewContent"] as? [String: Any])?["subtitle"] as? String) ?? "",
            url: ((post["mediumUrl"] as? String) ?? pageURL).components(separatedBy: "?")[0],
            wordCount: wordCount,
            readingTime: (readingTime * 10).rounded() / 10,
            publishedAt: publishedAt.int64Value,
            image: ((post["previewImage"] as? [String: Any])?["id"] as? String) ?? "",
            claps: (post["clapCount"] as? NSNumber)?.intValue,
            responses: ((post["postResponses"] as? [String: Any])?["count"] as? NSNumber)?.intValue
        )
    } catch {
        FileHandle.standardError.write(Data("! \(pageURL): \(error)\n".utf8))
        return nil
    }
}

let existing = (try? JSONDecoder().decode([CatalogEntry].self, from: Data(contentsOf: catalogFile))) ?? []
let sitemap = String(decoding: try await fetch(sitemapURL), as: UTF8.self)
let sitemapURLs = sitemap
    .components(separatedBy: "<loc>").dropFirst()
    .compactMap { $0.components(separatedBy: "</loc>").first }
var seenIDs = Set<String>()
let pageURLs = (existing.map(\.url) + sitemapURLs).filter { url in
    guard let id = postID(from: url) else { return false }
    return seenIDs.insert(id).inserted
}
print("\(existing.count) catalog articles + sitemap = \(pageURLs.count) posts to check")

var entries: [CatalogEntry] = []
await withTaskGroup(of: CatalogEntry?.self) { group in
    var pending = pageURLs.makeIterator()
    for _ in 0..<4 {
        if let next = pending.next() { group.addTask { await entry(for: next) } }
    }
    var done = 0
    while let result = await group.next() {
        done += 1
        if let result { entries.append(result) }
        if done % 50 == 0 { print("  \(done)/\(pageURLs.count)") }
        if let next = pending.next() { group.addTask { await entry(for: next) } }
    }
}
entries.sort { $0.publishedAt < $1.publishedAt }

let encoder = JSONEncoder()
encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
let json = try encoder.encode(entries)
try json.write(to: catalogFile)
try (Data("window.ARTICLES = ".utf8) + json + Data(";\n".utf8)).write(to: repoRoot.appendingPathComponent("app/data.js"))
print("wrote \(entries.count) articles")
