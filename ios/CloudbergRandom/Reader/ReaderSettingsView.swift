import SwiftUI

/// Reading preferences sheet. Changes apply live to the article behind it.
struct ReaderSettingsView: View {
    @Bindable var settings: ReaderSettings

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    themePicker
                    if settings.theme == .custom {
                        ColorPicker("Background", selection: color(\.customBackground), supportsOpacity: false)
                        ColorPicker("Text", selection: color(\.customText), supportsOpacity: false)
                    }
                }

                Section("Text") {
                    Picker("Font", selection: $settings.typeface) {
                        ForEach(ReaderSettings.Typeface.allCases) { typeface in
                            Text(typeface.name)
                                .font(Font(typeface.font(size: 17) as CTFont))
                                .tag(typeface)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    HStack(spacing: 16) {
                        Button { step(\.fontSize, by: -1, in: ReaderSettings.fontSizes) } label: {
                            Image(systemName: "textformat.size.smaller")
                        }
                        .accessibilityLabel("Smaller text")
                        Slider(value: $settings.fontSize, in: ReaderSettings.fontSizes, step: 1)
                        Button { step(\.fontSize, by: 1, in: ReaderSettings.fontSizes) } label: {
                            Image(systemName: "textformat.size.larger")
                        }
                        .accessibilityLabel("Larger text")
                    }
                    .buttonStyle(.borderless)
                    LabeledContent("Size", value: "\(Int(settings.fontSize)) pt")
                }

                Section("Layout") {
                    Picker("Alignment", selection: $settings.alignment) {
                        ForEach(ReaderSettings.TextAlignment.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Hyphenation", isOn: $settings.hyphenation)
                    Toggle("Indent paragraphs", isOn: $settings.indentParagraphs)
                    slider("Line spacing", value: $settings.lineHeight, in: ReaderSettings.lineHeights, step: 0.05,
                           label: String(format: "%.2f×", settings.lineHeight))
                    if !settings.indentParagraphs {
                        slider("Paragraph spacing", value: $settings.paragraphSpacing, in: ReaderSettings.paragraphSpacings, step: 0.1,
                               label: String(format: "%.1f em", settings.paragraphSpacing))
                    }
                    slider("Margins", value: $settings.margin, in: ReaderSettings.margins, step: 2,
                           label: "\(Int(settings.margin)) pt")
                    slider("Maximum line width", value: $settings.maxLineWidth, in: ReaderSettings.lineWidths, step: 20,
                           label: "\(Int(settings.maxLineWidth)) pt")
                    Button("Reset Text & Layout") { settings.resetLayout() }
                }

                Section {
                    Toggle("Keep screen on while reading", isOn: $settings.keepScreenOn)
                }
            }
            .navigationTitle("Reading")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Theme.accent)
    }

    private var themePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(ReaderSettings.ColorTheme.allCases) { theme in
                    let palette = settings.palette(for: theme)
                    Button {
                        settings.theme = theme
                    } label: {
                        VStack(spacing: 6) {
                            Text("Aa")
                                .font(Font(settings.typeface.font(size: 18) as CTFont))
                                .foregroundStyle(palette.text)
                                .frame(width: 52, height: 52)
                                .background(palette.background, in: Circle())
                                .overlay(
                                    Circle().strokeBorder(settings.theme == theme ? Theme.accent : Color.gray.opacity(0.35),
                                                          lineWidth: settings.theme == theme ? 3 : 1)
                                )
                            Text(theme.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(settings.theme == theme ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>,
                        step: Double, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title, value: label)
            Slider(value: value, in: range, step: step)
        }
    }

    private func step(_ keyPath: ReferenceWritableKeyPath<ReaderSettings, Double>, by amount: Double, in range: ClosedRange<Double>) {
        settings[keyPath: keyPath] = (settings[keyPath: keyPath] + amount).clamped(to: range)
    }

    private func color(_ keyPath: ReferenceWritableKeyPath<ReaderSettings, RGBA>) -> Binding<Color> {
        Binding(
            get: { settings[keyPath: keyPath].color },
            set: { settings[keyPath: keyPath] = RGBA($0) }
        )
    }
}
