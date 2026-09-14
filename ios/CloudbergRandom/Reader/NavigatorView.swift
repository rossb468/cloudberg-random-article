import SwiftUI

/// Sections and bookmarks for the open article, plus a position scrubber.
struct NavigatorView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case contents = "Contents", bookmarks = "Bookmarks"
        var id: String { rawValue }
    }

    let document: ReaderDocument
    let currentBlockID: String?
    @Binding var bookmarks: [Bookmark]
    var onNavigate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .contents
    @State private var scrubProgress: Double = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Jump to", value: "\(Int((scrubProgress * 100).rounded()))%")
                        Slider(value: $scrubProgress, in: 0...1) { editing in
                            guard !editing, let blockID = document.blockID(atProgress: scrubProgress) else { return }
                            go(to: blockID)
                        }
                    }
                }

                Picker("Show", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                switch tab {
                case .contents: contents
                case .bookmarks: bookmarkList
                }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            scrubProgress = currentBlockID.map(document.progress(at:)) ?? 0
        }
    }

    private var contents: some View {
        let current = currentBlockID.flatMap(document.landmark(containing:))
        return Section {
            ForEach(document.landmarks) { landmark in
                Button { go(to: landmark.blockID) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: icon(for: landmark.kind))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 20)
                        Text(landmark.title)
                            .foregroundStyle(.primary)
                            .fontWeight(landmark == current ? .semibold : .regular)
                            .lineLimit(2)
                        Spacer()
                        Text("\(Int((document.progress(at: landmark.blockID) * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityAddTraits(landmark == current ? .isSelected : [])
            }
        } footer: {
            if document.landmarks.count <= 1 {
                Text("This article has no section breaks.")
            }
        }
    }

    @ViewBuilder
    private var bookmarkList: some View {
        if bookmarks.isEmpty {
            Section {
                ContentUnavailableView(
                    "No Bookmarks",
                    systemImage: "bookmark",
                    description: Text("Tap the bookmark button while reading to mark the paragraph at the top of the screen.")
                )
            }
        } else {
            Section {
                ForEach(sortedBookmarks) { bookmark in
                    Button { go(to: bookmark.blockID) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bookmark.excerpt.isEmpty ? "Bookmark" : bookmark.excerpt)
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                            Text("\(Int((document.progress(at: bookmark.blockID) * 100).rounded()))% · \(bookmark.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let removed = offsets.map { sortedBookmarks[$0].id }
                    bookmarks.removeAll { removed.contains($0.id) }
                }
            }
        }
    }

    private var sortedBookmarks: [Bookmark] {
        bookmarks.sorted { (document.index(of: $0.blockID) ?? .max) < (document.index(of: $1.blockID) ?? .max) }
    }

    private func icon(for kind: ReaderDocument.Landmark.Kind) -> String {
        switch kind {
        case .start: "text.line.first.and.arrowtriangle.forward"
        case .heading: "textformat"
        case .section: "diamond"
        }
    }

    private func go(to blockID: String) {
        dismiss()
        onNavigate(blockID)
    }
}
