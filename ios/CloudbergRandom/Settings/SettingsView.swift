import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(OfflineLibrary.self) private var library
    @Environment(EngagementStore.self) private var engagement
    @Environment(ReadingStateStore.self) private var reading

    @State private var confirmingClearHistory = false
    @State private var confirmingRemoveDownloads = false
    @State private var webPage: IdentifiableURL?

    private let articles = ArticleStore.all

    var body: some View {
        @Bindable var settings = settings
        @Bindable var library = library
        NavigationStack {
            Form {
                Section("Articles") {
                    Toggle("In-progress section", isOn: $settings.showInProgressSection)
                    Toggle("Reading progress on rows", isOn: $settings.showReadingProgress)
                    NavigationLink {
                        SortOptionsView()
                    } label: {
                        LabeledContent("Sort options", value: "\(settings.availableSorts().count) shown")
                    }
                }

                Section {
                    Toggle("Hide discussion and engagement", isOn: $settings.hideSocial)
                } footer: {
                    Text("Hides Reddit discussions, claps and upvotes, and the engagement sorts.")
                }

                Section("Reading") {
                    Toggle("Reopen last article at launch", isOn: $settings.reopenLastArticle)
                    Toggle("Hide controls while scrolling", isOn: $settings.autoHideReaderControls)
                    Toggle("Open links in the app", isOn: $settings.openLinksInApp)
                }

                Section("Random") {
                    Toggle("Don't repeat the last article", isOn: $settings.avoidRecentRandom)
                }

                Section {
                    Toggle("Include images", isOn: $library.includeImages)
                    Toggle("Keep articles you open", isOn: $settings.saveArticlesOnOpen)
                    LabeledContent("Downloaded", value: "\(library.downloadedCount(of: articles)) of \(articles.count)")
                    LabeledContent("Storage used", value: ByteCountFormatter.string(fromByteCount: library.storageBytes, countStyle: .file))
                    Button("Remove All Downloads", role: .destructive) { confirmingRemoveDownloads = true }
                } header: {
                    Text("Downloads")
                } footer: {
                    Text("The whole archive with images is about 3 GB.")
                }

                if !settings.hideSocial {
                    Section {
                        if engagement.isRefreshing {
                            Button("Stop Updating", systemImage: "stop.circle") { engagement.cancelRefresh() }
                            ProgressView(value: Double(engagement.refreshProgress.done),
                                         total: Double(max(engagement.refreshProgress.total, 1)))
                                .tint(Theme.accent)
                        } else {
                            Button("Update Medium Stats", systemImage: "arrow.clockwise") {
                                engagement.refreshMediumStats()
                            }
                        }
                    } header: {
                        Text("Engagement")
                    } footer: {
                        Text("Re-reads every article page from Medium for current claps and responses. Reddit numbers come from an archive and don't change.")
                    }
                }

                Section {
                    Toggle("Sync with iCloud", isOn: $settings.syncWithiCloud)
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Keeps reading positions, bookmarks, settings and the article you have open the same on your other devices. Downloads stay on each device.")
                }

                Section("Reading History") {
                    LabeledContent("Articles started", value: "\(startedCount)")
                    Button("Clear Reading History", role: .destructive) { confirmingClearHistory = true }
                }

                Section {
                    LabeledContent("Articles in catalog", value: "\(articles.count)")
                    LabeledContent("Version", value: Bundle.main.versionDescription)
                    Button("Admiral Cloudberg on Medium", systemImage: "safari") {
                        webPage = URL(string: "https://admiralcloudberg.medium.com").map(IdentifiableURL.init)
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("All writing belongs to Admiral Cloudberg.")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Clear reading history?", isPresented: $confirmingClearHistory, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { reading.clearAll() }
            } message: {
                Text("Forgets every reading position and bookmark. Downloads are kept.")
            }
            .confirmationDialog("Remove all downloads?", isPresented: $confirmingRemoveDownloads, titleVisibility: .visible) {
                Button("Remove All", role: .destructive) { library.removeAll() }
            } message: {
                Text("Articles stay readable with a connection. Reading positions and bookmarks are kept.")
            }
            .sheet(item: $webPage) { page in
                SafariView(url: page.url).ignoresSafeArea()
            }
        }
        .tint(Theme.accent)
    }

    private var startedCount: Int {
        reading.progressByPostID.values.filter { $0 > 0.02 }.count
    }
}

/// Which sorts the Articles menu offers.
private struct SortOptionsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            Section {
                ForEach(ArticleSort.allCases) { sort in
                    Button {
                        toggle(sort)
                    } label: {
                        HStack {
                            Label(sort.label, systemImage: sort.systemImage)
                                .foregroundStyle(.primary)
                            Spacer()
                            if settings.enabledSorts.contains(sort) {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .disabled(sort.isEngagement && settings.hideSocial)
                }
            } footer: {
                Text(settings.hideSocial
                     ? "Engagement sorts are unavailable while discussion and engagement are hidden."
                     : "At least one sort stays on.")
            }
        }
        .navigationTitle("Sort Options")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ sort: ArticleSort) {
        var enabled = settings.enabledSorts
        if enabled.contains(sort) {
            enabled.remove(sort)
        } else {
            enabled.insert(sort)
        }
        settings.enabledSorts = enabled
    }
}

extension Bundle {
    var versionDescription: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
