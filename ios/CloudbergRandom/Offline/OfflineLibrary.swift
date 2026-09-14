import Foundation
import Observation
import UIKit

enum OfflineStatus: Equatable {
    case notDownloaded
    case queued
    case downloading(progress: Double)
    case failed(String)
    /// Text saved; images not (yet) saved.
    case textOnly
    case complete
}

/// Saves articles (Medium's structured body plus images) under Application
/// Support so they can be read without a connection.
///
///     OfflineArticles/
///       Posts/<postID>.json
///       Images/<imageID>
///       Images/<postID>.complete   marker: every image for the post is saved
@MainActor
@Observable
final class OfflineLibrary {
    static let shared = OfflineLibrary()

    /// Images are fetched at this width: full-width on a 3x iPhone, with some
    /// room to zoom.
    nonisolated static let imageWidth = 1200
    private static let articleConcurrency = 3
    private static let imageConcurrency = 4

    private(set) var savedPostIDs: Set<String> = []
    private(set) var completeImagePostIDs: Set<String> = []
    private(set) var activity: [String: OfflineStatus] = [:]
    private(set) var isDownloadingAll = false
    private(set) var storageBytes: Int64 = 0

    var includeImages: Bool {
        didSet { UserDefaults.standard.set(includeImages, forKey: "offline.includeImages") }
    }

    private let client: MediumClient
    private var batchTask: Task<Void, Never>?

    nonisolated static let rootDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("OfflineArticles", isDirectory: true)
    }()
    nonisolated static let postsDirectory = rootDirectory.appendingPathComponent("Posts", isDirectory: true)
    nonisolated static let imagesDirectory = rootDirectory.appendingPathComponent("Images", isDirectory: true)

    init(client: MediumClient = MediumClient()) {
        self.client = client
        includeImages = UserDefaults.standard.object(forKey: "offline.includeImages") as? Bool ?? true
        for directory in [Self.postsDirectory, Self.imagesDirectory] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let posts = (try? FileManager.default.contentsOfDirectory(atPath: Self.postsDirectory.path)) ?? []
        savedPostIDs = Set(posts.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) })
        let images = (try? FileManager.default.contentsOfDirectory(atPath: Self.imagesDirectory.path)) ?? []
        completeImagePostIDs = Set(images.filter { $0.hasSuffix(".complete") }.map { String($0.dropLast(9)) })
        refreshStorageSize()
    }

    // MARK: - Status

    func status(for article: Article) -> OfflineStatus {
        let id = article.postID
        if let active = activity[id] { return active }
        guard savedPostIDs.contains(id) else { return .notDownloaded }
        return completeImagePostIDs.contains(id) || !includeImages ? .complete : .textOnly
    }

    func isAvailableOffline(_ article: Article) -> Bool {
        savedPostIDs.contains(article.postID)
    }

    func downloadedCount(of articles: [Article]) -> Int {
        articles.filter { status(for: $0) == .complete }.count
    }

    // MARK: - Reading

    /// The saved copy if there is one, otherwise fetched from Medium (and saved,
    /// so anything you've opened stays readable offline).
    func post(for article: Article) async throws -> MediumPost {
        if let saved = Self.savedPost(id: article.postID) { return saved }
        let post = try await fetchWithRetry(article)
        try save(post)
        EngagementStore.shared.record(claps: post.clapCount, responses: post.responseCount, for: post.id)
        return post
    }

    nonisolated static func savedPost(id: String) -> MediumPost? {
        guard let data = try? Data(contentsOf: postFile(id: id)) else { return nil }
        return try? JSONDecoder().decode(MediumPost.self, from: data)
    }

    nonisolated static func localImageFile(id: String) -> URL? {
        let file = imageFile(id: id)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    // MARK: - Downloading

    func download(_ article: Article) {
        guard activity[article.postID] == nil else { return }
        activity[article.postID] = .queued
        Task { await downloadRecordingFailure(article) }
    }

    func downloadAll(_ articles: [Article]) {
        guard batchTask == nil else { return }
        let pending = articles.filter { status(for: $0) != .complete && activity[$0.postID] == nil }
        guard !pending.isEmpty else { return }
        for article in pending { activity[article.postID] = .queued }
        isDownloadingAll = true
        // Downloading everything takes a while; don't let the screen lock stop it.
        UIApplication.shared.isIdleTimerDisabled = true

        batchTask = Task {
            await withTaskGroup(of: Void.self) { group in
                var queue = pending.makeIterator()
                for _ in 0..<Self.articleConcurrency {
                    guard let next = queue.next() else { break }
                    group.addTask { await self.downloadRecordingFailure(next) }
                }
                while await group.next() != nil {
                    guard !Task.isCancelled, let next = queue.next() else { continue }
                    group.addTask { await self.downloadRecordingFailure(next) }
                }
            }
            for (id, state) in activity where state == .queued { activity[id] = nil }
            isDownloadingAll = false
            UIApplication.shared.isIdleTimerDisabled = false
            batchTask = nil
            refreshStorageSize()
        }
    }

    func stopDownloadingAll() {
        batchTask?.cancel()
    }

    func remove(_ article: Article) {
        let id = article.postID
        if let post = Self.savedPost(id: id) {
            for imageID in post.imageIDs { try? FileManager.default.removeItem(at: Self.imageFile(id: imageID)) }
        }
        try? FileManager.default.removeItem(at: Self.postFile(id: id))
        try? FileManager.default.removeItem(at: Self.completeMarker(postID: id))
        savedPostIDs.remove(id)
        completeImagePostIDs.remove(id)
        activity[id] = nil
        refreshStorageSize()
    }

    func removeAll() {
        stopDownloadingAll()
        try? FileManager.default.removeItem(at: Self.rootDirectory)
        for directory in [Self.postsDirectory, Self.imagesDirectory] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        savedPostIDs = []
        completeImagePostIDs = []
        activity = [:]
        refreshStorageSize()
    }

    private func downloadRecordingFailure(_ article: Article) async {
        let id = article.postID
        do {
            try Task.checkCancellation()
            activity[id] = .downloading(progress: 0)
            let post = try await post(for: article)
            if includeImages && !completeImagePostIDs.contains(id) {
                try await downloadImages(of: post)
            }
            activity[id] = nil
        } catch is CancellationError {
            activity[id] = nil
        } catch let error as URLError where error.code == .cancelled {
            activity[id] = nil
        } catch {
            activity[id] = .failed(error.localizedDescription)
        }
    }

    private func downloadImages(of post: MediumPost) async throws {
        let imageIDs = Array(Set(post.imageIDs))
        var finished = 0
        try await withThrowingTaskGroup(of: Void.self) { group in
            var queue = imageIDs.makeIterator()
            for _ in 0..<Self.imageConcurrency {
                guard let next = queue.next() else { break }
                group.addTask { try await Self.downloadImage(id: next) }
            }
            while try await group.next() != nil {
                finished += 1
                activity[post.id] = .downloading(progress: Double(finished) / Double(max(imageIDs.count, 1)))
                if let next = queue.next() {
                    group.addTask { try await Self.downloadImage(id: next) }
                }
            }
        }
        FileManager.default.createFile(atPath: Self.completeMarker(postID: post.id).path, contents: nil)
        completeImagePostIDs.insert(post.id)
    }

    nonisolated private static func downloadImage(id: String) async throws {
        let destination = imageFile(id: id)
        guard !FileManager.default.fileExists(atPath: destination.path),
              let url = MediumImage.url(id: id, width: imageWidth) else { return }
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        // A broken image shouldn't fail the whole article.
        guard status == 200 else { return }
        try data.write(to: destination, options: .atomic)
    }

    /// Medium rate-limits bursts of requests; back off and try again.
    private func fetchWithRetry(_ article: Article) async throws -> MediumPost {
        var delay: UInt64 = 3
        for attempt in 1... {
            do {
                return try await client.fetchPost(for: article)
            } catch MediumClientError.httpStatus(let status) where [403, 429, 503].contains(status) && attempt < 4 {
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay *= 3
            }
        }
        fatalError("unreachable")
    }

    private func save(_ post: MediumPost) throws {
        try JSONEncoder().encode(post).write(to: Self.postFile(id: post.id), options: .atomic)
        savedPostIDs.insert(post.id)
    }

    private func refreshStorageSize() {
        Task.detached(priority: .utility) {
            let size = Self.directorySize(Self.rootDirectory)
            await MainActor.run { self.storageBytes = size }
        }
    }

    // MARK: - Paths

    nonisolated private static func postFile(id: String) -> URL {
        postsDirectory.appendingPathComponent("\(id).json")
    }

    nonisolated private static func imageFile(id: String) -> URL {
        // Image ids look like "1*AbC.jpeg"; keep them filename-safe.
        let safe = id.replacingOccurrences(of: "/", with: "_")
        return imagesDirectory.appendingPathComponent(safe)
    }

    nonisolated private static func completeMarker(postID: String) -> URL {
        imagesDirectory.appendingPathComponent("\(postID).complete")
    }

    nonisolated private static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
