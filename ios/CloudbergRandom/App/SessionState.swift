import Foundation
import Observation

/// What the app was showing when it was last closed, so a relaunch picks up
/// where you left off: the tab, the article open in each tab, the random card,
/// and where the article list was scrolled and searched.
///
/// Reading positions themselves live in `ReadingStateStore`; this only records
/// what was on screen.
@MainActor
@Observable
final class SessionState: CloudSyncable {
    static let shared = SessionState()

    enum Tab: String, Codable, Hashable {
        case random, articles, settings
    }

    private struct Stored: Codable, Equatable {
        var tab: Tab = .random
        var randomPostID: String?
        var openPostIDs: [String: String] = [:]
        var listTopPostID: String?
        var listSearch = ""
    }

    private static let key = "session.state"

    private let defaults: UserDefaults
    private var stored: Stored { didSet { scheduleSave() } }
    private var saveTask: Task<Void, Never>?
    private(set) var cloudUpdatedAt = Date.distantPast
    let cloudKey = "session"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stored = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
        cloudUpdatedAt = defaults.object(forKey: Self.key + ".updatedAt") as? Date ?? .distantPast
    }

    var tab: Tab {
        get { stored.tab }
        set { stored.tab = newValue }
    }

    var randomPostID: String? {
        get { stored.randomPostID }
        set { stored.randomPostID = newValue }
    }

    var listTopPostID: String? {
        get { stored.listTopPostID }
        set { stored.listTopPostID = newValue }
    }

    var listSearch: String {
        get { stored.listSearch }
        set { stored.listSearch = newValue }
    }

    func openPostID(for tab: Tab) -> String? {
        stored.openPostIDs[tab.rawValue]
    }

    func setOpenPostID(_ postID: String?, for tab: Tab) {
        stored.openPostIDs[tab.rawValue] = postID
    }


    /// Writes immediately, for when the app is going to the background.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        write()
    }

    /// State changes as fast as a finger moves, so writes are coalesced.
    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            saveTask = nil
            write()
        }
    }

    private func write() {
        cloudUpdatedAt = .now
        defaults.set(try? JSONEncoder().encode(stored), forKey: Self.key)
        defaults.set(cloudUpdatedAt, forKey: Self.key + ".updatedAt")
        CloudSync.shared.push(self)
    }

    func cloudPayload() -> Data? {
        try? JSONEncoder().encode(stored)
    }

    /// Picked up where another device left off, so this one opens there too.
    func applyCloudPayload(_ data: Data) {
        guard let incoming = try? JSONDecoder().decode(Stored.self, from: data), incoming != stored else { return }
        defaults.set(data, forKey: Self.key)
        stored = incoming
    }
}
