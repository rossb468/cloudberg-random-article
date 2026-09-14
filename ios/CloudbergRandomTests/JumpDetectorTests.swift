import Foundation
import Testing
@testable import CloudbergRandom

struct JumpDetectorTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func steadyReadingIsNotAJump() {
        var detector = JumpDetector()
        for step in 0..<60 {
            let now = start.addingTimeInterval(Double(step) * 3)
            #expect(detector.update(blockID: "b\(step)", progress: Double(step) * 0.01, at: now) == nil)
            detector.tick(at: now.addingTimeInterval(2))
        }
    }

    @Test func leapingAwayOffersTheSettledPosition() {
        var detector = JumpDetector()
        _ = detector.update(blockID: "b50", progress: 0.5, at: start)
        detector.tick(at: start.addingTimeInterval(5))
        let jump = detector.update(blockID: "b0", progress: 0, at: start.addingTimeInterval(6))
        #expect(jump == .init(fromBlockID: "b50", fromProgress: 0.5, toProgress: 0))
    }

    @Test func reportsEachJumpOnce() {
        var detector = JumpDetector()
        _ = detector.update(blockID: "b50", progress: 0.5, at: start)
        detector.tick(at: start.addingTimeInterval(5))
        #expect(detector.update(blockID: "b0", progress: 0, at: start.addingTimeInterval(6)) != nil)
        #expect(detector.update(blockID: "b1", progress: 0.01, at: start.addingTimeInterval(6.1)) == nil)
    }

    @Test func aFastFlingCountsFromTheLastSettledSpot() {
        var detector = JumpDetector()
        _ = detector.update(blockID: "b20", progress: 0.2, at: start)
        detector.tick(at: start.addingTimeInterval(5))
        // Passing through blocks quickly never settles on them.
        _ = detector.update(blockID: "b22", progress: 0.22, at: start.addingTimeInterval(5.1))
        detector.tick(at: start.addingTimeInterval(5.2))
        let jump = detector.update(blockID: "b40", progress: 0.4, at: start.addingTimeInterval(5.3))
        #expect(jump?.fromBlockID == "b20")
    }

    @Test func settlingSomewhereNewAllowsAnotherJump() {
        var detector = JumpDetector()
        _ = detector.update(blockID: "b50", progress: 0.5, at: start)
        detector.tick(at: start.addingTimeInterval(5))
        _ = detector.update(blockID: "b0", progress: 0, at: start.addingTimeInterval(6))
        detector.tick(at: start.addingTimeInterval(10))
        let jump = detector.update(blockID: "b90", progress: 0.9, at: start.addingTimeInterval(11))
        #expect(jump?.fromBlockID == "b0")
    }
}
