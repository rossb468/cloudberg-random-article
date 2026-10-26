import Foundation
import Testing
@testable import CloudbergRandom

@MainActor
struct CloudSyncTests {
    /// Stands in for iCloud: the same contract, in memory.
    private final class FakeCloud: CloudStore {
        var values: [String: Data] = [:]

        override var isAvailable: Bool { true }

        override func start(onRemoteChange: @escaping ([String]) -> Void) {}

        override func data(forKey key: String) -> Data? { values[key] }

        override func set(_ data: Data?, forKey key: String) {
            if let data { values[key] = data } else { values[key] = nil }
        }

        override func keys(withPrefix prefix: String) -> [String] {
            values.keys.filter { $0.hasPrefix(prefix) }
        }

        override func removeAll(withPrefix prefix: String) {
            for key in keys(withPrefix: prefix) { values[key] = nil }
        }
    }

    private func settings() -> (AppSettings, UserDefaults) {
        let defaults = UserDefaults(suiteName: "cloud.tests.\(UUID().uuidString)")!
        return (AppSettings(defaults: defaults), defaults)
    }

    @Test func pushesSettingsToTheCloud() throws {
        let cloud = FakeCloud()
        let sync = CloudSync(cloud: cloud)
        let (local, _) = settings()
        local.hideSocial = true

        sync.push(local)

        let data = try #require(cloud.values["settings.app"])
        let record = try JSONDecoder().decode(CloudRecord.self, from: data)
        #expect(record.updatedAt == local.cloudUpdatedAt)
        #expect(String(decoding: record.payload, as: UTF8.self).contains("\"hideSocial\":true"))
    }

    @Test func newerCloudSettingsWin() throws {
        let cloud = FakeCloud()
        let (sender, _) = settings()
        sender.hideSocial = true
        sender.showInProgressSection = false
        CloudSync(cloud: cloud).push(sender)

        let (receiver, _) = settings()
        #expect(receiver.hideSocial == false)

        let data = try #require(cloud.values["settings.app"])
        let record = try JSONDecoder().decode(CloudRecord.self, from: data)
        receiver.applyCloudPayload(record.payload)

        #expect(receiver.hideSocial)
        #expect(receiver.showInProgressSection == false)
    }

    @Test func olderCloudSettingsAreIgnored() throws {
        let cloud = FakeCloud()
        let sync = CloudSync(cloud: cloud)
        let (old, _) = settings()
        old.hideSocial = true
        sync.push(old)

        // A device that changed the same setting more recently.
        let (current, _) = settings()
        current.hideSocial = false
        #expect(current.cloudUpdatedAt > old.cloudUpdatedAt)

        let data = try #require(cloud.values["settings.app"])
        let record = try JSONDecoder().decode(CloudRecord.self, from: data)
        #expect(record.updatedAt < current.cloudUpdatedAt)
    }

    @Test func readingPositionsTravelPerArticle() throws {
        let cloud = FakeCloud()
        let sync = CloudSync(cloud: cloud)
        let position = ReadingState(blockID: "p_42", progress: 0.42, updatedAt: .now)
        let payload = try JSONEncoder().encode(position)

        sync.pushReading(payload, updatedAt: position.updatedAt!, postID: "abc123def456")

        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReadingStateStore(directory: directory)
        let data = try #require(cloud.values["reading.abc123def456"])
        let record = try JSONDecoder().decode(CloudRecord.self, from: data)
        store.applyCloudReading(record.payload, updatedAt: record.updatedAt, postID: "abc123def456")

        #expect(store.state(for: "abc123def456").blockID == "p_42")
        #expect(store.progress(for: "abc123def456") == 0.42)
    }

    @Test func anOlderPositionDoesNotOverwriteANewerOne() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReadingStateStore(directory: directory)

        var here = store.state(for: "abc123def456")
        here.blockID = "p_90"
        here.progress = 0.9
        here.updatedAt = .now
        store.save(here, for: "abc123def456")

        let stale = ReadingState(blockID: "p_10", progress: 0.1, updatedAt: .now.addingTimeInterval(-600))
        store.applyCloudReading(try JSONEncoder().encode(stale), updatedAt: stale.updatedAt!, postID: "abc123def456")

        #expect(store.state(for: "abc123def456").blockID == "p_90")
    }
}
