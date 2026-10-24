import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CloudbergRandom

struct AnimatedImageTests {
    /// A 2x2 frame, shaded so frames differ from each other.
    private func frame(shade: Double) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: shade, green: shade, blue: shade, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return try #require(context.makeImage())
    }

    private func imageData(type: UTType, frames: Int) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, type.identifier as CFString, frames, nil)
        )
        if type == .gif {
            CGImageDestinationSetProperties(
                destination,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
            )
        }
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary
        for index in 0..<frames {
            let shade = Double(index) / Double(max(frames - 1, 1))
            CGImageDestinationAddImage(destination, try frame(shade: shade), frameProperties)
        }
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func countsFramesInAnAnimatedGIF() throws {
        let gif = try imageData(type: .gif, frames: 3)
        #expect(AnimatedImage.frameCount(of: gif) == 3)
        #expect(AnimatedImage.isAnimated(gif))
    }

    @Test func stillImagesAreNotAnimated() throws {
        let png = try imageData(type: .png, frames: 1)
        #expect(AnimatedImage.frameCount(of: png) == 1)
        #expect(!AnimatedImage.isAnimated(png))

        // A single-frame GIF is a still too.
        #expect(!AnimatedImage.isAnimated(try imageData(type: .gif, frames: 1)))
    }

    @Test func rubbishDataIsNotAnimated() {
        #expect(!AnimatedImage.isAnimated(Data("not an image".utf8)))
        #expect(AnimatedImage.frameCount(of: Data()) == 0)
    }
}
