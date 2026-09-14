import Foundation

extension ReaderDocument {
    /// A place the previous/next buttons stop at: a section or a bookmark.
    struct Stop: Equatable {
        enum Kind: Equatable { case landmark, bookmark }
        let blockIndex: Int
        let blockID: String
        let kind: Kind
    }

    func stops(bookmarks: [Bookmark]) -> [Stop] {
        let landmarkStops = landmarks.map { Stop(blockIndex: $0.blockIndex, blockID: $0.blockID, kind: .landmark) }
        let bookmarkStops = bookmarks.compactMap { bookmark in
            index(of: bookmark.blockID).map { Stop(blockIndex: $0, blockID: bookmark.blockID, kind: .bookmark) }
        }
        // A bookmark on a section's first block is one stop, shown as a bookmark.
        var byIndex: [Int: Stop] = [:]
        for stop in landmarkStops + bookmarkStops { byIndex[stop.blockIndex] = stop }
        return byIndex.values.sorted { $0.blockIndex < $1.blockIndex }
    }

    func nextStop(after blockID: String?, bookmarks: [Bookmark]) -> Stop? {
        let current = blockID.flatMap(index(of:)) ?? -1
        return stops(bookmarks: bookmarks).first { $0.blockIndex > current }
    }

    func previousStop(before blockID: String?, bookmarks: [Bookmark]) -> Stop? {
        guard let current = blockID.flatMap(index(of:)) else { return nil }
        return stops(bookmarks: bookmarks).last { $0.blockIndex < current }
    }

    /// The landmark whose section contains a block.
    func landmark(containing blockID: String) -> Landmark? {
        guard let index = index(of: blockID) else { return landmarks.first }
        return landmarks.last { $0.blockIndex <= index } ?? landmarks.first
    }
}
