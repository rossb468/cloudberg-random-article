import SwiftUI
import UIKit

/// Reading preferences, shared by every article and persisted across launches.
@MainActor
@Observable
final class ReaderSettings {
    static let shared = ReaderSettings()

    enum Typeface: String, CaseIterable, Identifiable, Codable {
        case newYork, charter, georgia, iowan, palatino, athelas, avenirNext, sanFrancisco, rounded

        var id: String { rawValue }

        var name: String {
            switch self {
            case .newYork: "New York"
            case .charter: "Charter"
            case .georgia: "Georgia"
            case .iowan: "Iowan"
            case .palatino: "Palatino"
            case .athelas: "Athelas"
            case .avenirNext: "Avenir Next"
            case .sanFrancisco: "San Francisco"
            case .rounded: "SF Rounded"
            }
        }

        func font(size: CGFloat, bold: Bool = false, italic: Bool = false) -> UIFont {
            let base: UIFont = switch self {
            case .newYork: Self.system(size: size, design: .serif)
            case .sanFrancisco: .systemFont(ofSize: size)
            case .rounded: Self.system(size: size, design: .rounded)
            case .charter: UIFont(name: "Charter-Roman", size: size) ?? .systemFont(ofSize: size)
            case .georgia: UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
            case .iowan: UIFont(name: "IowanOldStyle-Roman", size: size) ?? .systemFont(ofSize: size)
            case .palatino: UIFont(name: "Palatino-Roman", size: size) ?? .systemFont(ofSize: size)
            case .athelas: UIFont(name: "Athelas-Regular", size: size) ?? .systemFont(ofSize: size)
            case .avenirNext: UIFont(name: "AvenirNext-Regular", size: size) ?? .systemFont(ofSize: size)
            }
            var traits = base.fontDescriptor.symbolicTraits
            if bold { traits.insert(.traitBold) }
            if italic { traits.insert(.traitItalic) }
            guard traits != base.fontDescriptor.symbolicTraits,
                  let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
            return UIFont(descriptor: descriptor, size: size)
        }

        private static func system(size: CGFloat, design: UIFontDescriptor.SystemDesign) -> UIFont {
            let descriptor = UIFont.systemFont(ofSize: size).fontDescriptor.withDesign(design)
            return descriptor.map { UIFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size)
        }
    }

    enum ColorTheme: String, CaseIterable, Identifiable, Codable {
        case paper, sepia, sage, dusk, night, black, custom

        var id: String { rawValue }
        var name: String { rawValue.capitalized }
    }

    enum TextAlignment: String, CaseIterable, Identifiable, Codable {
        case leading, justified

        var id: String { rawValue }
        var name: String { self == .leading ? "Left" : "Justified" }
    }

    struct Palette: Equatable {
        let background: Color
        let text: Color
        let secondaryText: Color
        let accent: Color
        let colorScheme: ColorScheme
    }

    var typeface: Typeface = .newYork { didSet { save() } }
    var fontSize: Double = 19 { didSet { save() } }
    /// Multiple of the font's natural line height.
    var lineHeight: Double = 1.45 { didSet { save() } }
    /// Space between paragraphs, in multiples of the font size.
    var paragraphSpacing: Double = 0.9 { didSet { save() } }
    /// Indent the first line of paragraphs instead of spacing them apart.
    var indentParagraphs = false { didSet { save() } }
    var margin: Double = 22 { didSet { save() } }
    var maxLineWidth: Double = 680 { didSet { save() } }
    var alignment: TextAlignment = .leading { didSet { save() } }
    var hyphenation = true { didSet { save() } }
    var theme: ColorTheme = .night { didSet { save() } }
    var customBackground = RGBA(red: 0.13, green: 0.12, blue: 0.10) { didSet { save() } }
    var customText = RGBA(red: 0.90, green: 0.86, blue: 0.78) { didSet { save() } }
    var keepScreenOn = false { didSet { save() } }

    static let fontSizes: ClosedRange<Double> = 13...34
    static let lineHeights: ClosedRange<Double> = 1.0...2.2
    static let paragraphSpacings: ClosedRange<Double> = 0...2
    static let margins: ClosedRange<Double> = 8...64
    static let lineWidths: ClosedRange<Double> = 420...1000

    private let defaults: UserDefaults
    private var loading = false
    private static let storageKey = "reader.settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    var palette: Palette {
        switch theme {
        case .paper:
            Palette(background: .hex(0xFBFAF7), text: .hex(0x1D1D1F), secondaryText: .hex(0x6E6E73), accent: .hex(0xA85A12), colorScheme: .light)
        case .sepia:
            Palette(background: .hex(0xF4ECD8), text: .hex(0x3B2F1E), secondaryText: .hex(0x7A6A55), accent: .hex(0x96541A), colorScheme: .light)
        case .sage:
            Palette(background: .hex(0xE4ECE0), text: .hex(0x22301F), secondaryText: .hex(0x5C6B57), accent: .hex(0x3D7447), colorScheme: .light)
        case .dusk:
            Palette(background: .hex(0x2E3138), text: .hex(0xDCD8D0), secondaryText: .hex(0x9C9DA2), accent: .hex(0xE8A33D), colorScheme: .dark)
        case .night:
            Palette(background: .hex(0x0F1115), text: .hex(0xD5D8DF), secondaryText: .hex(0x8A91A0), accent: .hex(0xE8A33D), colorScheme: .dark)
        case .black:
            Palette(background: .black, text: .hex(0xC7C7C7), secondaryText: .hex(0x7A7A7A), accent: .hex(0xE8A33D), colorScheme: .dark)
        case .custom:
            Palette(
                background: customBackground.color,
                text: customText.color,
                secondaryText: customText.color.opacity(0.62),
                accent: Theme.accent,
                colorScheme: customBackground.luminance > 0.5 ? .light : .dark
            )
        }
    }

    /// Restores the text and layout defaults, leaving colors alone.
    func resetLayout() {
        typeface = .newYork
        fontSize = 19
        lineHeight = 1.45
        paragraphSpacing = 0.9
        indentParagraphs = false
        margin = 22
        maxLineWidth = 680
        alignment = .leading
        hyphenation = true
    }

    // MARK: - Persistence

    private struct Stored: Codable {
        var typeface: Typeface?
        var fontSize: Double?
        var lineHeight: Double?
        var paragraphSpacing: Double?
        var indentParagraphs: Bool?
        var margin: Double?
        var maxLineWidth: Double?
        var alignment: TextAlignment?
        var hyphenation: Bool?
        var theme: ColorTheme?
        var customBackground: RGBA?
        var customText: RGBA?
        var keepScreenOn: Bool?
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        loading = true
        defer { loading = false }
        stored.typeface.map { typeface = $0 }
        stored.fontSize.map { fontSize = $0.clamped(to: Self.fontSizes) }
        stored.lineHeight.map { lineHeight = $0.clamped(to: Self.lineHeights) }
        stored.paragraphSpacing.map { paragraphSpacing = $0.clamped(to: Self.paragraphSpacings) }
        stored.indentParagraphs.map { indentParagraphs = $0 }
        stored.margin.map { margin = $0.clamped(to: Self.margins) }
        stored.maxLineWidth.map { maxLineWidth = $0.clamped(to: Self.lineWidths) }
        stored.alignment.map { alignment = $0 }
        stored.hyphenation.map { hyphenation = $0 }
        stored.theme.map { theme = $0 }
        stored.customBackground.map { customBackground = $0 }
        stored.customText.map { customText = $0 }
        stored.keepScreenOn.map { keepScreenOn = $0 }
    }

    private func save() {
        guard !loading else { return }
        let stored = Stored(
            typeface: typeface, fontSize: fontSize, lineHeight: lineHeight,
            paragraphSpacing: paragraphSpacing, indentParagraphs: indentParagraphs,
            margin: margin, maxLineWidth: maxLineWidth, alignment: alignment,
            hyphenation: hyphenation, theme: theme, customBackground: customBackground,
            customText: customText, keepScreenOn: keepScreenOn
        )
        defaults.set(try? JSONEncoder().encode(stored), forKey: Self.storageKey)
    }
}

/// A persistable color.
struct RGBA: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        (self.red, self.green, self.blue, self.alpha) = (red, green, blue, alpha)
    }

    init(_ color: Color) {
        var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 1)
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }

    var color: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }

    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
}

extension Color {
    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
