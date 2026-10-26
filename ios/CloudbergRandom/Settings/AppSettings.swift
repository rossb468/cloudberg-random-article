import Foundation
import Observation

/// Settings for how the app behaves, separate from `ReaderSettings`, which is
/// about how an article looks while you read it.
@MainActor
@Observable
final class AppSettings: CloudSyncable {
    static let shared = AppSettings()

    private struct Stored: Codable, Equatable {
        var showInProgressSection = true
        var showReadingProgress = true
        var hideSocial = false
        var enabledSorts: [String] = ArticleSort.allCases.map(\.rawValue)
        var avoidRecentRandom = true
        var saveArticlesOnOpen = true
        var autoHideReaderControls = true
        var openLinksInApp = true
        var reopenLastArticle = true
        var syncWithiCloud = true
    }

    private static let key = "app.settings"

    private let defaults: UserDefaults
    private var stored: Stored { didSet { save() } }
    private(set) var cloudUpdatedAt = Date.distantPast
    let cloudKey = "settings.app"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stored = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
        cloudUpdatedAt = defaults.object(forKey: Self.key + ".updatedAt") as? Date ?? .distantPast
    }

    /// Articles you've started, listed above the rest.
    var showInProgressSection: Bool {
        get { stored.showInProgressSection }
        set { stored.showInProgressSection = newValue }
    }

    /// The "42% read" bar on list rows.
    var showReadingProgress: Bool {
        get { stored.showReadingProgress }
        set { stored.showReadingProgress = newValue }
    }

    /// Hides Reddit discussions, clap and upvote counts, and the engagement
    /// sorts, for reading without the running commentary.
    var hideSocial: Bool {
        get { stored.hideSocial }
        set { stored.hideSocial = newValue }
    }

    /// Which sorts appear in the Articles sort menu.
    var enabledSorts: Set<ArticleSort> {
        get {
            let enabled = Set(stored.enabledSorts.compactMap(ArticleSort.init(rawValue:)))
            return enabled.isEmpty ? [.newest] : enabled
        }
        set {
            let kept = newValue.isEmpty ? [ArticleSort.newest] : Array(newValue)
            stored.enabledSorts = kept.map(\.rawValue)
        }
    }

    /// Sorts offered in the menu, in their usual order, minus anything hidden.
    func availableSorts() -> [ArticleSort] {
        let enabled = enabledSorts
        return ArticleSort.allCases.filter { sort in
            enabled.contains(sort) && !(hideSocial && sort.isEngagement)
        }
    }

    /// Don't show the same random article twice in a row.
    var avoidRecentRandom: Bool {
        get { stored.avoidRecentRandom }
        set { stored.avoidRecentRandom = newValue }
    }

    /// Keep articles you open, so they're readable offline later.
    var saveArticlesOnOpen: Bool {
        get { stored.saveArticlesOnOpen }
        set { stored.saveArticlesOnOpen = newValue }
    }

    /// Fade the reader's controls away while you scroll down.
    var autoHideReaderControls: Bool {
        get { stored.autoHideReaderControls }
        set { stored.autoHideReaderControls = newValue }
    }

    /// Open links in the app rather than handing them to Safari.
    var openLinksInApp: Bool {
        get { stored.openLinksInApp }
        set { stored.openLinksInApp = newValue }
    }

    /// Reopen the article you were reading when the app starts.
    var reopenLastArticle: Bool {
        get { stored.reopenLastArticle }
        set { stored.reopenLastArticle = newValue }
    }

    var syncWithiCloud: Bool {
        get { stored.syncWithiCloud }
        set { stored.syncWithiCloud = newValue }
    }

    private func save() {
        cloudUpdatedAt = .now
        defaults.set(try? JSONEncoder().encode(stored), forKey: Self.key)
        defaults.set(cloudUpdatedAt, forKey: Self.key + ".updatedAt")
        CloudSync.shared.push(self)
    }

    func cloudPayload() -> Data? {
        try? JSONEncoder().encode(stored)
    }

    func applyCloudPayload(_ data: Data) {
        guard let incoming = try? JSONDecoder().decode(Stored.self, from: data), incoming != stored else { return }
        // Straight to the field: writing through `stored` would push it back.
        defaults.set(data, forKey: Self.key)
        stored = incoming
    }
}
