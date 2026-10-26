import Foundation
import Observation

/// Anything whose state is small enough to live in iCloud's key-value store.
@MainActor
protocol CloudSyncable: AnyObject {
    /// The key this state lives under.
    var cloudKey: String { get }
    /// When it last changed here, for deciding which side is newer.
    var cloudUpdatedAt: Date { get }
    func cloudPayload() -> Data?
    func applyCloudPayload(_ data: Data)
}

/// Carries a store's state with the time it was written, so the newer side of
/// a disagreement wins.
struct CloudRecord: Codable {
    var updatedAt: Date
    var payload: Data
}

/// Keeps reading positions, bookmarks, settings and what was last on screen the
/// same across a person's devices.
@MainActor
@Observable
final class CloudSync {
    static let shared = CloudSync()

    static let readingPrefix = "reading."

    private(set) var lastSyncedAt: Date?

    @ObservationIgnored private let cloud: CloudStore
    @ObservationIgnored private var syncables: [String: any CloudSyncable] = [:]
    @ObservationIgnored private var isEnabled: () -> Bool = { true }
    @ObservationIgnored private var readingStore: (any CloudReadingSyncable)?

    init(cloud: CloudStore = .shared) {
        self.cloud = cloud
    }

    var isAvailable: Bool { cloud.isAvailable }

    func start(syncables: [any CloudSyncable], reading: any CloudReadingSyncable, enabled: @escaping () -> Bool) {
        self.syncables = Dictionary(uniqueKeysWithValues: syncables.map { ($0.cloudKey, $0) })
        readingStore = reading
        isEnabled = enabled
        cloud.start { [weak self] keys in
            self?.pull(keys: keys)
        }
        // Whatever iCloud already knows, on first run on a new device.
        pull(keys: Array(syncables.map(\.cloudKey)) + cloud.keys(withPrefix: Self.readingPrefix))
        for syncable in syncables { push(syncable) }
    }

    func push(_ syncable: any CloudSyncable) {
        guard isEnabled(), let payload = syncable.cloudPayload() else { return }
        write(CloudRecord(updatedAt: syncable.cloudUpdatedAt, payload: payload), forKey: syncable.cloudKey)
    }

    func pushReading(_ payload: Data, updatedAt: Date, postID: String) {
        guard isEnabled() else { return }
        write(CloudRecord(updatedAt: updatedAt, payload: payload), forKey: Self.readingPrefix + postID)
    }

    func removeAllReading() {
        guard isEnabled() else { return }
        cloud.removeAll(withPrefix: Self.readingPrefix)
    }

    private func write(_ record: CloudRecord, forKey key: String) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        cloud.set(data, forKey: key)
        lastSyncedAt = .now
    }

    /// Takes iCloud's copy when it's newer than what's here.
    private func pull(keys: [String]) {
        guard isEnabled() else { return }
        for key in keys {
            guard let data = cloud.data(forKey: key),
                  let record = try? JSONDecoder().decode(CloudRecord.self, from: data) else { continue }
            if key.hasPrefix(Self.readingPrefix) {
                let postID = String(key.dropFirst(Self.readingPrefix.count))
                readingStore?.applyCloudReading(record.payload, updatedAt: record.updatedAt, postID: postID)
            } else if let syncable = syncables[key], record.updatedAt > syncable.cloudUpdatedAt {
                syncable.applyCloudPayload(record.payload)
            }
        }
        lastSyncedAt = .now
    }
}

/// Reading state is one record per article rather than one blob.
@MainActor
protocol CloudReadingSyncable: AnyObject {
    func applyCloudReading(_ payload: Data, updatedAt: Date, postID: String)
}
