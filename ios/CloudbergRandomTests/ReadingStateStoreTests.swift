import Foundation
import Testing
@testable import CloudbergRandom

@MainActor
struct ReadingStateStoreTests {
    private func temporaryStore() -> (ReadingStateStore, URL) {
        let directory = URL.temporaryDirectory.appendingPathComponent("ReadingState-\(UUID().uuidString)")
        return (ReadingStateStore(directory: directory), directory)
    }

    @Test func unknownArticlesStartEmpty() {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(store.state(for: "abc123def456") == ReadingState())
    }

    @Test func positionsAndBookmarksSurviveARestart() {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var state = store.state(for: "abc123def456")
        state.blockID = "p_42"
        state.progress = 0.42
        state.bookmarks = [Bookmark(blockID: "p_12", excerpt: "Something to come back to")]
        store.save(state, for: "abc123def456")

        // A second store reads the same files, as a later launch would.
        let reopened = ReadingStateStore(directory: directory)
        let restored = reopened.state(for: "abc123def456")
        #expect(restored.blockID == "p_42")
        #expect(restored.progress == 0.42)
        #expect(restored.bookmarks.map(\.blockID) == ["p_12"])
    }

    @Test func articlesKeepSeparatePositions() {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var first = store.state(for: "aaaaaaaaaaaa")
        first.blockID = "p_1"
        store.save(first, for: "aaaaaaaaaaaa")
        var second = store.state(for: "bbbbbbbbbbbb")
        second.blockID = "p_2"
        store.save(second, for: "bbbbbbbbbbbb")

        #expect(store.state(for: "aaaaaaaaaaaa").blockID == "p_1")
        #expect(store.state(for: "bbbbbbbbbbbb").blockID == "p_2")
    }
}
