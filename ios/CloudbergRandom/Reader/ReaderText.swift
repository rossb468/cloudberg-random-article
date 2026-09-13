import SwiftUI
import UIKit

/// Builds a block's attributed text from Medium's markup ranges and the
/// current reading settings.
@MainActor
enum ReaderTypesetter {
    static func text(_ text: String, markups: [MediumMarkup], style: ReaderDocument.TextStyle,
                     settings: ReaderSettings) -> NSAttributedString {
        let palette = settings.palette
        let size = CGFloat(settings.fontSize)

        let (font, color, alignment): (UIFont, Color, NSTextAlignment) = switch style {
        case .body, .bullet, .numbered:
            (settings.typeface.font(size: size), palette.text,
             settings.alignment == .justified ? .justified : .natural)
        case .heading:
            (settings.typeface.font(size: size * 1.3, bold: true), palette.text, .natural)
        case .subheading:
            (settings.typeface.font(size: size * 1.12, bold: true), palette.text, .natural)
        case .blockquote:
            (settings.typeface.font(size: size * 0.94, italic: true), palette.secondaryText, .natural)
        case .pullQuote:
            (settings.typeface.font(size: size * 1.2, italic: true), palette.text, .center)
        case .code:
            (.monospacedSystemFont(ofSize: size * 0.82, weight: .regular), palette.text, .natural)
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = CGFloat(style == .heading ? max(1.1, settings.lineHeight * 0.85) : settings.lineHeight)
        paragraph.alignment = alignment
        // Justified text needs hyphenation to avoid rivers; ragged-right text only
        // hyphenates very long words.
        paragraph.hyphenationFactor = !settings.hyphenation ? 0 : settings.alignment == .justified ? 0.9 : 0.2
        if settings.indentParagraphs && style == .body {
            paragraph.firstLineHeadIndent = size * 1.5
        }

        var body = text
        var prefixLength = 0
        switch style {
        case .bullet:
            body = "•\t" + text
            prefixLength = 2
        case .numbered(let number):
            body = "\(number).\t" + text
            prefixLength = "\(number).\t".utf16.count
        default:
            break
        }
        if prefixLength > 0 {
            let indent = size * 1.4
            paragraph.tabStops = [NSTextTab(textAlignment: .natural, location: indent)]
            paragraph.defaultTabInterval = indent
            paragraph.headIndent = indent
        }

        let result = NSMutableAttributedString(string: body, attributes: [
            .font: font,
            .foregroundColor: UIColor(color),
            .paragraphStyle: paragraph,
        ])
        apply(markups, to: result, offset: prefixLength, codeSize: size * 0.82)
        return result
    }

    static func caption(_ text: String, markups: [MediumMarkup], settings: ReaderSettings) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineHeightMultiple = 1.15
        let size = max(12, CGFloat(settings.fontSize) * 0.7)
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: size),
            .foregroundColor: UIColor(settings.palette.secondaryText),
            .paragraphStyle: paragraph,
        ])
        apply(markups, to: result, offset: 0, codeSize: size)
        return result
    }

    /// Medium markup ranges are UTF-16 offsets, the same units as NSRange.
    private static func apply(_ markups: [MediumMarkup], to string: NSMutableAttributedString, offset: Int, codeSize: CGFloat) {
        let length = string.length
        for markup in markups {
            let start = min(markup.start + offset, length)
            let end = min(markup.end + offset, length)
            guard end > start else { continue }
            let range = NSRange(location: start, length: end - start)
            switch markup.kind {
            case .bold:
                addTrait(.traitBold, in: range, of: string)
            case .italic:
                addTrait(.traitItalic, in: range, of: string)
            case .code:
                string.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: codeSize, weight: .regular), range: range)
            case .link:
                if let href = markup.href, let url = URL(string: href) {
                    string.addAttribute(.link, value: url, range: range)
                }
            case .unknown:
                break
            }
        }
    }

    private static func addTrait(_ trait: UIFontDescriptor.SymbolicTraits, in range: NSRange, of string: NSMutableAttributedString) {
        string.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? UIFont else { return }
            let traits = font.fontDescriptor.symbolicTraits.union(trait)
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                string.addAttribute(.font, value: UIFont(descriptor: descriptor, size: font.pointSize), range: subrange)
            }
        }
    }
}

/// Selectable rich text that sizes itself to the proposed width. A UITextView
/// rather than SwiftUI Text because Text can't justify or hyphenate.
struct ReaderText: UIViewRepresentable {
    let attributedText: NSAttributedString
    let linkColor: Color
    var onOpenLink: (URL) -> Void = { _ in }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onOpenLink = onOpenLink
        view.linkTextAttributes = [
            .foregroundColor: UIColor(linkColor),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        if !view.attributedText.isEqual(to: attributedText) {
            view.attributedText = attributedText
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitting.height))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenLink: onOpenLink)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onOpenLink: (URL) -> Void

        init(onOpenLink: @escaping (URL) -> Void) {
            self.onOpenLink = onOpenLink
        }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            guard case .link(let url) = textItem.content else { return defaultAction }
            return UIAction { [onOpenLink] _ in onOpenLink(url) }
        }
    }
}
