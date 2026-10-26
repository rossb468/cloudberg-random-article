#!/usr/bin/env swift
// Draws the placeholder app icon.
//
//   swift scripts/make-app-icon.swift
//
// A diamond on a night sky: the "◊◊◊" Admiral Cloudberg puts between an
// article's sections, over the reader's own dark palette.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = repoRoot.appendingPathComponent("ios/CloudbergRandom/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

let context = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

func color(_ red: Double, _ green: Double, _ blue: Double) -> CGColor {
    CGColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

let night = color(0x0F, 0x11, 0x15)
let horizonGlow = color(0x1E, 0x27, 0x38)
let amber = color(0xE8, 0xA3, 0x3D)

// Night sky, lighter towards the horizon.
context.setFillColor(night)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [horizonGlow, night] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: size / 2, y: size * 0.34),
    end: CGPoint(x: size / 2, y: size),
    options: []
)

// The horizon.
context.setStrokeColor(amber.copy(alpha: 0.35)!)
context.setLineWidth(size * 0.012)
context.move(to: CGPoint(x: size * 0.14, y: size * 0.33))
context.addLine(to: CGPoint(x: size * 0.86, y: size * 0.33))
context.strokePath()

// A diamond, as between an article's sections.
func diamond(center: CGPoint, radius: Double) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: center.x, y: center.y + radius))
    path.addLine(to: CGPoint(x: center.x + radius * 0.74, y: center.y))
    path.addLine(to: CGPoint(x: center.x, y: center.y - radius))
    path.addLine(to: CGPoint(x: center.x - radius * 0.74, y: center.y))
    path.closeSubpath()
    return path
}

let center = CGPoint(x: size / 2, y: size * 0.56)
context.setStrokeColor(amber)
context.setLineWidth(size * 0.035)
context.setLineJoin(.round)
context.addPath(diamond(center: center, radius: size * 0.26))
context.strokePath()

context.setFillColor(amber.copy(alpha: 0.9)!)
context.addPath(diamond(center: center, radius: size * 0.1))
context.fillPath()

// The two smaller diamonds that flank it in the text.
for offset in [-1.0, 1.0] {
    context.setFillColor(amber.copy(alpha: 0.55)!)
    context.addPath(diamond(center: CGPoint(x: center.x + offset * size * 0.345, y: center.y), radius: size * 0.05))
    context.fillPath()
}

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
print("wrote \(output.path)")
