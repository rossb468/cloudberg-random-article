import Foundation

/// iCloud's key-value store, wrapped so the rest of the app can hand it records
/// without caring whether iCloud is available or switched on.
///
/// Key-value storage suits what's being synced: reading positions, bookmarks,
/// settings and what was last on screen are all small. Downloaded articles and
/// images stay on each device — they run to gigabytes, and a device can fetch
/// them again itself.
@MainActor
class CloudStore {
    static let shared = CloudStore()

    /// Apple's limits: 1 MB in total, 1024 keys.
    static let keyLimit = 1024

    private let store: NSUbiquitousKeyValueStore?
    private var observer: NSObjectProtocol?
    /// Called with the keys iCloud changed elsewhere.
    private var onRemoteChange: (([String]) -> Void)?

    init(store: NSUbiquitousKeyValueStore? = .default) {
        self.store = store
    }

    var isAvailable: Bool {
        store != nil && FileManager.default.ubiquityIdentityToken != nil
    }

    func start(onRemoteChange: @escaping ([String]) -> Void) {
        guard let store else { return }
        self.onRemoteChange = onRemoteChange
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] notification in
            let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            MainActor.assumeIsolated { self?.onRemoteChange?(keys) }
        }
        store.synchronize()
    }

    func data(forKey key: String) -> Data? {
        store?.data(forKey: key)
    }

    func set(_ data: Data?, forKey key: String) {
        guard let store else { return }
        if let data {
            store.set(data, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
    }

    func keys(withPrefix prefix: String) -> [String] {
        (store?.dictionaryRepresentation.keys ?? [:].keys).filter { $0.hasPrefix(prefix) }
    }

    func removeAll(withPrefix prefix: String) {
        for key in keys(withPrefix: prefix) {
            store?.removeObject(forKey: key)
        }
    }
}
