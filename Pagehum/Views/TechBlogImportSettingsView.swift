// Modified for Pagehum: unified application and command-line naming.
import SwiftUI

/// A dedicated destination shared by Settings and the Add Content shortcut.
struct TechBlogImportSettingsView: View {
    @ObservedObject var viewModel: ReaderModel

    var body: some View {
        #if os(macOS)
        DesktopPage(width: 640) {
            DesktopHeading(title: "Tech blog imports", subtitle: "Find your next listen on Hacker News.")
            settingsContent
        }
        #else
        ScrollView {
            settingsContent.padding(20)
        }
        .background(Color.platformGroupedBackground)
        .navigationTitle("Tech Blog Imports")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Choose what interests you. Matching articles are saved to your library, ready to listen.")
                .font(.callout).foregroundStyle(.secondary)

            settingsSection("Topics", subtitle: "Match any selected topic in story titles and URLs.") {
                ForEach(TechBlogTopic.allCases) { topic in
                    if topic != TechBlogTopic.allCases.first { Divider() }
                    Toggle(isOn: Binding(
                        get: { viewModel.techBlogSettings.topics.contains(topic) },
                        set: { enabled in
                            if enabled { viewModel.techBlogSettings.topics.insert(topic) }
                            else { viewModel.techBlogSettings.topics.remove(topic) }
                        }
                    )) {
                        Label {
                            Text(topic.title)
                        } icon: {
                            Image(systemName: topic.symbol).frame(width: 22)
                        }
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.switch)
                    .padding(.vertical, 4)
                }
            }
            .disabled(viewModel.isLoading)

            settingsSection("Story filters", subtitle: "Freshness is based on the Hacker News submission date. The article itself may be older.") {
                LabeledContent("Stories") {
                    Picker("Stories", selection: $viewModel.techBlogSettings.feed) {
                        ForEach(TechBlogFeed.allCases) { feed in Text(feed.title).tag(feed) }
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .trailing)
                }
                Divider()
                LabeledContent("Submitted within") {
                    Picker("Submitted within", selection: $viewModel.techBlogSettings.freshnessDays) {
                        Text("24 hours").tag(1)
                        Text("3 days").tag(3)
                        Text("7 days").tag(7)
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .trailing)
                }
                Divider()
                Stepper(value: $viewModel.techBlogSettings.minimumScore, in: 0...1000, step: 10) {
                    LabeledContent("Minimum HN score") {
                        Text(viewModel.techBlogSettings.minimumScore == 0 ? "Any score" : "\(viewModel.techBlogSettings.minimumScore)")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(viewModel.isLoading)

            settingsSection("Import limits", subtitle: "Saved links are skipped. Scanning more stories may take longer.") {
                Stepper(value: $viewModel.techBlogSettings.importLimit, in: 1...50) {
                    LabeledContent("Maximum articles") {
                        Text("\(viewModel.techBlogSettings.importLimit)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Divider()
                LabeledContent("Stories to scan") {
                    Picker("Stories to scan", selection: $viewModel.techBlogSettings.storyCount) {
                        ForEach([100, 200, 500], id: \.self) { count in Text("\(count)").tag(count) }
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .disabled(viewModel.isLoading)

            VStack(alignment: .leading, spacing: 12) {
                if viewModel.techBlogSettings.topics.isEmpty {
                    Label("Choose at least one topic to import articles.", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
                TechBlogImportButton(viewModel: viewModel)
                Text("Preferences save automatically and apply to imports from Add Content.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = viewModel.techBlogMessage {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
                URLImportStatusView(viewModel: viewModel)
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
        }
        .pickerStyle(.menu)
    }

    private func settingsSection<Content: View>(_ title: LocalizedStringKey, subtitle: LocalizedStringKey,
                                               @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 14, content: content)
                .padding(18)
                .background(techBlogPanelColor, in: RoundedRectangle(cornerRadius: 14))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TechBlogSettingsLabel: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "newspaper")
                .font(.title3).foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text("Tech Blog Imports").foregroundStyle(.primary)
                Text("Topics, story filters, and import limits")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// One-tap discovery uses the same saved preferences as the settings screen.
struct TechBlogQuickImportView<SettingsLink: View>: View {
    @ObservedObject var viewModel: ReaderModel
    @ViewBuilder var settingsLink: SettingsLink

    private var selectedTopics: String {
        TechBlogTopic.allCases.filter { viewModel.techBlogSettings.topics.contains($0) }
            .map(\.title).joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "newspaper")
                    .font(.title2).foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Discover tech blogs").font(.headline)
                    Text("Fresh finds from Hacker News, saved to your library.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if selectedTopics.isEmpty {
                Text("Choose at least one topic in import settings to get started.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text(selectedTopics).font(.subheadline.weight(.medium))
                Text("Up to \(viewModel.techBlogSettings.importLimit) articles per import")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    TechBlogImportButton(viewModel: viewModel)
                    settingsLink
                }
                VStack(alignment: .leading, spacing: 14) {
                    TechBlogImportButton(viewModel: viewModel)
                    settingsLink
                }
            }
            if let message = viewModel.techBlogMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(techBlogPanelColor, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor.opacity(0.18)))
    }
}

private struct TechBlogImportButton: View {
    @ObservedObject var viewModel: ReaderModel

    var body: some View {
        Button {
            Task { await viewModel.importLatestTechBlogs() }
        } label: {
            Label("Import latest articles", systemImage: "square.and.arrow.down")
        }
        #if os(macOS)
        .buttonStyle(DesktopButtonStyle(primary: true))
        #else
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        #endif
        .disabled(viewModel.isLoading || viewModel.techBlogSettings.topics.isEmpty)
    }
}

private var techBlogPanelColor: Color {
    #if os(macOS)
    DesktopStyle.panel
    #else
    Color.secondaryGroupedBackground
    #endif
}

private extension TechBlogTopic {
    var symbol: String {
        switch self {
        case .ai: "sparkles"
        case .backend: "server.rack"
        case .scaling: "chart.line.uptrend.xyaxis"
        case .interview: "person.2"
        }
    }
}
