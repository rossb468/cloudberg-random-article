import ImageIO
import SwiftUI
import UIKit

enum AnimatedImage {
    /// Frames ImageIO can decode from encoded image data.
    static func frameCount(of data: Data) -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return 0 }
        return CGImageSourceGetCount(source)
    }

    static func isAnimated(_ data: Data) -> Bool {
        frameCount(of: data) > 1
    }
}

/// Plays animated image data. Articles embed GIFs — some of them hundreds of
/// frames and tens of megabytes — so the data stays encoded and ImageIO decodes
/// a frame at a time rather than holding them all in memory.
struct AnimatedImageView: UIViewRepresentable {
    let data: Data
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeUIView(context: Context) -> AnimatedImageHostView {
        let view = AnimatedImageHostView()
        view.clipsToBounds = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: AnimatedImageHostView, context: Context) {
        view.contentMode = contentMode
        view.play(data)
    }
}

/// A UIImageView that animates encoded image data.
final class AnimatedImageHostView: UIImageView {
    private var playing: Data?
    /// Bumped to end the running animation; its callback checks this and stops.
    private var generation = 0

    func play(_ data: Data) {
        guard playing != data else { return }
        playing = data
        generation += 1
        // The first frame, so there's something to lay out and to show when
        // animation is off.
        image = UIImage(data: data)
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        let generation = generation
        CGAnimateImageDataWithBlock(data as CFData, nil) { [weak self] _, frame, stop in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else {
                    stop.pointee = true
                    return
                }
                self.image = UIImage(cgImage: frame)
            }
        }
    }

    deinit {
        generation += 1
    }
}
