import Foundation

/// Notices when the reading position leaps somewhere far away — a status-bar
/// tap that scrolls to the top, a hard fling, a jump from the contents list — so
/// the reader can offer to go back to where you were actually reading.
///
/// A position counts as "where you were reading" once you've stayed on it for
/// `settleInterval`. Moving more than `threshold` of the article away from that
/// position before settling somewhere new is a jump.
struct JumpDetector {
    struct Jump: Equatable {
        let fromBlockID: String
        let fromProgress: Double
        let toProgress: Double
    }

    var settleInterval: TimeInterval = 1.2
    var threshold: Double = 0.08

    private(set) var settled: (blockID: String, progress: Double)?
    private var current: (blockID: String, progress: Double, since: Date)?
    private var reportedFrom: String?

    /// Call whenever the top visible block changes.
    mutating func update(blockID: String, progress: Double, at now: Date) -> Jump? {
        guard let settled else {
            self.settled = (blockID, progress)
            current = (blockID, progress, now)
            return nil
        }
        if current?.blockID != blockID {
            current = (blockID, progress, now)
        }
        guard abs(progress - settled.progress) >= threshold, reportedFrom != settled.blockID else { return nil }
        reportedFrom = settled.blockID
        return Jump(fromBlockID: settled.blockID, fromProgress: settled.progress, toProgress: progress)
    }

    /// Call periodically so a position can settle even when nothing is scrolling.
    mutating func tick(at now: Date) {
        guard let current, now.timeIntervalSince(current.since) >= settleInterval else { return }
        if settled?.blockID != current.blockID {
            settled = (current.blockID, current.progress)
            reportedFrom = nil
        }
    }
}
